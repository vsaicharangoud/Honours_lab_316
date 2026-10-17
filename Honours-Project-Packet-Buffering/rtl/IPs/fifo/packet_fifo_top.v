/*
 * ============================================================================
 * File: packet_fifo_top.v
 * Project: Reliable Data Transport System SoC
 * Description: Top-Level Asynchronous Packet FIFO Core with CDC Diagnostics.
 *              Integrates:
 *                1. Dual-clock Asynchronous FIFO Core (async_fifo_top)
 *                2. 37-bit Payload Width: {tlast, tkeep[3:0], tdata[31:0]}
 *                3. AXI4-Lite Slave Register Interface (Base: 0x0007_0000)
 *                4. Streaming Packet Master Interface to CRC Checker (m_axis_*)
 *                5. Streaming Packet Slave Interface from RX source (s_axis_*)
 *                6. Runtime CDC Self-Diagnosis Unit & PIC Interrupt Generation
 * ============================================================================
 */

// timescale defined via compiler flag -timescale=1ns/1ps

`include "fifo_defines.vh"

module packet_fifo_top #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer FIFO_DEPTH     = 16,  // Must be power of 2
    parameter integer SYNC_STAGES    = 2
)(
    // ------------------------------------------------------------------------
    // Clock and Reset Signals
    // ------------------------------------------------------------------------
    input  wire                          aclk,        // SoC System Clock (Read & AXI domain)
    input  wire                          aresetn,     // SoC Active-Low Reset
    input  wire                          wr_clk,      // Write Domain Clock (RX / CDC domain)
    input  wire                          wr_rst_n,    // Write Domain Active-Low Reset

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (CPU Configuration & Status @ 0x0007_0000)
    // ------------------------------------------------------------------------
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                    s_axi_awprot,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,

    input  wire [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,

    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,

    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,

    output wire [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready,

    // ------------------------------------------------------------------------
    // Upstream Streaming Interface (Path In: From UART/SPI RX domain)
    // Clocked by wr_clk
    // ------------------------------------------------------------------------
    input  wire [31:0]                   s_axis_tdata,
    input  wire [3:0]                    s_axis_tkeep,
    input  wire                          s_axis_tlast,
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,

    // ------------------------------------------------------------------------
    // Downstream Streaming Interface (Path Out: To CRC Checker s_axis_*)
    // Clocked by aclk (rd_clk)
    // ------------------------------------------------------------------------
    output wire [31:0]                   m_axis_tdata,
    output wire [3:0]                    m_axis_tkeep,
    output wire                          m_axis_tlast,
    output wire                          m_axis_tvalid,
    input  wire                          m_axis_tready,

    // ------------------------------------------------------------------------
    // Dedicated Hardware Flags & Interrupt to SoC
    // ------------------------------------------------------------------------
    output wire                          fifo_full_o,     // FIFO Full flag (Write domain)
    output wire                          fifo_empty_o,    // FIFO Empty flag (Read domain)
    output wire                          fifo_irq_o,      // Aggregated Interrupt to VeeR PIC
    output wire                          fifo_error_o     // Latched error flag for system logging
);

    // ------------------------------------------------------------------------
    // Payload Configuration: 37 bits = {tlast, tkeep[3:0], tdata[31:0]}
    // ------------------------------------------------------------------------
    localparam PAYLOAD_WIDTH = 37;
    localparam ADDR_WIDTH    = $clog2(FIFO_DEPTH);
    localparam PTR_WIDTH     = ADDR_WIDTH + 1;

    // ------------------------------------------------------------------------
    // Internal Wires between AXI Slave, FIFO Core, and Datapath
    // ------------------------------------------------------------------------
    // CPU direct write port
    wire        cpu_wr_en;
    wire [31:0] cpu_wr_data;
    wire [3:0]  cpu_wr_be;
    wire        cpu_wr_last;

    // CPU direct read port
    wire        cpu_rd_en;
    wire [31:0] cpu_rd_data;
    wire        cpu_rd_valid;

    // Control wires
    wire        ctrl_enable;
    wire        ctrl_soft_reset;
    wire        ctrl_stream_en;
    wire [15:0] almost_full_thresh;
    wire [15:0] almost_empty_thresh;
    wire [5:0]  diag_clear;

    // Status wires from FIFO core
    wire        core_wr_full;
    wire        core_wr_overflow;
    wire        core_rd_empty;
    wire        core_rd_valid;
    wire        core_rd_underflow;

    // Diagnostic wires from fifo_diag
    wire        wr_gray_error;
    wire        wr_overflow_sticky;
    wire        wr_pointer_stuck;
    wire        rd_gray_error;
    wire        rd_underflow_sticky;
    wire        rd_pointer_stuck;

    // Occupancy & Tracking
    reg  [15:0] wr_occupancy;
    reg  [15:0] rd_occupancy;
    wire        almost_full;
    wire        almost_empty;
    reg  [31:0] packet_count;

    // Core read & write signals
    wire                      fifo_wr_en;
    wire [PAYLOAD_WIDTH-1:0]  fifo_wr_payload;
    wire                      fifo_rd_en;
    wire [PAYLOAD_WIDTH-1:0]  fifo_rd_payload;

    // ------------------------------------------------------------------------
    // Direct Output Assignments
    // ------------------------------------------------------------------------
    assign fifo_full_o  = core_wr_full;
    assign fifo_empty_o = core_rd_empty;
    assign fifo_error_o = wr_overflow_sticky || rd_underflow_sticky ||
                          wr_gray_error || rd_gray_error ||
                          wr_pointer_stuck || rd_pointer_stuck;

    // ------------------------------------------------------------------------
    // Write Domain Datapath Multiplexing
    // Upstream Stream (s_axis) vs CPU AXI injection
    // ------------------------------------------------------------------------
    // Stream ready whenever FIFO is not full and enabled
    assign s_axis_tready = !core_wr_full && ctrl_enable;

    // If streaming input is active, it takes priority; otherwise CPU write port
    wire stream_write_req = s_axis_tvalid && ctrl_enable;
    wire cpu_write_req    = cpu_wr_en && ctrl_enable;

    assign fifo_wr_en = stream_write_req ? 1'b1 :
                        cpu_write_req    ? 1'b1 : 1'b0;

    assign fifo_wr_payload = stream_write_req ?
                             {s_axis_tlast, s_axis_tkeep, s_axis_tdata} :
                             {cpu_wr_last, (cpu_wr_be != 4'd0 ? cpu_wr_be : 4'b1111), cpu_wr_data};

    // ------------------------------------------------------------------------
    // Synchronize Write-Domain Diagnostics into aclk
    // ------------------------------------------------------------------------
    reg [2:0] wr_diag_sync1;
    reg [2:0] wr_diag_sync2;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_diag_sync1 <= 3'b0;
            wr_diag_sync2 <= 3'b0;
        end else begin
            wr_diag_sync1 <= {wr_pointer_stuck, wr_overflow_sticky, wr_gray_error};
            wr_diag_sync2 <= wr_diag_sync1;
        end
    end

    wire aclk_wr_gray_error      = wr_diag_sync2[0];
    wire aclk_wr_overflow_sticky = wr_diag_sync2[1];
    wire aclk_wr_pointer_stuck   = wr_diag_sync2[2];

    // ------------------------------------------------------------------------
    // Read Domain Datapath & AXI4-Stream Master
    //
    // fifo_mem has a 1-cycle REGISTERED read: data appears at fifo_rd_payload
    // exactly one posedge after rd_en is asserted.
    //
    // States:
    //   SM_IDLE    — FIFO empty or streaming disabled.
    //                Issues rd_en=1 when can_issue.  → SM_PENDING.
    //
    //   SM_PENDING — rd_en was issued last cycle; waiting one cycle for the
    //                RAM result.  Loads out_reg from fifo_rd_payload.
    //                Does NOT issue a new rd_en (avoids free-running address
    //                during stalls).  → SM_HOLD.
    //
    //   SM_HOLD    — out_reg holds valid data; m_axis_tvalid = 1.
    //                - Backpressure (tready=0): hold state, no action.
    //                - stream_pop + can_issue: issue rd_en this cycle for
    //                  the next word, transition to SM_PENDING to wait for
    //                  the RAM result.  → SM_PENDING.
    //                - stream_pop + !can_issue: FIFO drained.  → SM_IDLE.
    //
    // Throughput: 2 cycles per word (1 fetch + 1 present).  This is correct
    // for a packet-buffering FIFO where backpressure safety takes priority.
    //
    // m_axis_tvalid is COMBINATORIAL from rd_state (stable between edges
    // because rd_state is registered).
    // ------------------------------------------------------------------------
    localparam SM_IDLE    = 2'd0;
    localparam SM_PENDING = 2'd1;
    localparam SM_HOLD    = 2'd2;
    localparam SM_STREAM  = 2'd3;  // unused

    reg [1:0]               rd_state;
    reg [PAYLOAD_WIDTH-1:0] out_reg;

    assign m_axis_tdata  = out_reg[31:0];
    assign m_axis_tkeep  = out_reg[35:32];
    assign m_axis_tlast  = out_reg[36];
    assign m_axis_tvalid = (rd_state == SM_HOLD) && ctrl_enable && ctrl_stream_en;

    wire stream_pop  = m_axis_tvalid && m_axis_tready;
    wire can_issue   = !core_rd_empty && ctrl_enable && ctrl_stream_en;

    // fifo_rd_en: assert when a new RAM read should be issued.
    //
    // The registered-read RAM (fifo_mem) has 1-cycle latency: data appears
    // at fifo_rd_payload exactly one posedge AFTER rd_en is asserted.
    // rd_domain advances rd_bin_ptr (and therefore rd_addr) whenever
    // rd_allow = rd_en && !rd_empty.  During a SM_HOLD backpressure stall
    // rd_en is 0, so rd_addr is frozen.
    //
    // The previous design asserted rd_en in BOTH SM_IDLE and SM_PENDING.
    // While SM_PENDING is waiting for word0 to arrive it also prefetched
    // word1 (advancing rd_bin_ptr to addr=2).  During any subsequent stall
    // the RAM free-runs at addr=2, so when stream_pop finally fires the
    // fifo_rd_payload holds word2, not word1 — silently skipping word1.
    //
    // Fix: issue rd_en only from SM_IDLE (first fetch) and from SM_HOLD on
    // stream_pop (next fetch).  SM_PENDING never issues rd_en; it merely
    // waits the one RAM-latency cycle for the result of the previous rd_en.
    // SM_HOLD transitions back through SM_PENDING for each subsequent word,
    // guaranteeing that fifo_rd_payload is always correct when it is loaded.
    //
    //   SM_IDLE    + can_issue              : first fetch → SM_PENDING
    //   SM_HOLD    + stream_pop + can_issue : next fetch  → SM_PENDING
    //   CPU-mode direct read (streaming disabled).
    assign fifo_rd_en = ((rd_state == SM_IDLE && can_issue) ||
                         (rd_state == SM_HOLD && stream_pop && can_issue))
                        ? 1'b1
                        : (cpu_rd_en && !core_rd_empty && !ctrl_stream_en);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn || ctrl_soft_reset) begin
            rd_state <= SM_IDLE;
            out_reg  <= {PAYLOAD_WIDTH{1'b0}};
        end else begin
            case (rd_state)
                // SM_IDLE: issue rd_en this cycle → wait for RAM.
                SM_IDLE: begin
                    if (can_issue)
                        rd_state <= SM_PENDING;
                end

                // SM_PENDING: word arrives this cycle (RAM latency satisfied).
                // Load it into out_reg and present it next cycle (SM_HOLD).
                // No rd_en is issued here — the address must stay stable.
                SM_PENDING: begin
                    out_reg  <= fifo_rd_payload;   // wordN valid now
                    rd_state <= SM_HOLD;
                end

                // SM_HOLD: out_reg = wordN, tvalid = 1.
                SM_HOLD: begin
                    if (stream_pop) begin
                        if (can_issue) begin
                            // wordN accepted.  rd_en is being issued this cycle
                            // (combinatorially above); the RAM result will arrive
                            // after one posedge.  Go through SM_PENDING to wait
                            // for that result before presenting the next word.
                            // This avoids the free-running-address hazard that
                            // caused word-skipping under backpressure.
                            rd_state <= SM_PENDING;
                        end else begin
                            // FIFO drained.
                            rd_state <= SM_IDLE;
                        end
                    end
                    // No stream_pop: backpressure — hold state unchanged.
                end

                default: rd_state <= SM_IDLE;
            endcase
        end
    end

    // CPU direct read data (bypass stream pipeline)
    assign cpu_rd_data  = fifo_rd_payload[31:0];
    assign cpu_rd_valid = !core_rd_empty;

    // ------------------------------------------------------------------------
    // Packet Counter & Occupancy Tracking
    // ------------------------------------------------------------------------
    wire stream_active = m_axis_tvalid;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            packet_count <= 32'd0;
            rd_occupancy <= 16'd0;
        end else if (ctrl_soft_reset) begin
            packet_count <= 32'd0;
            rd_occupancy <= 16'd0;
        end else begin
            // Increment packet count when a packet successfully completes downstream
            if (stream_pop && m_axis_tlast) begin
                packet_count <= packet_count + 1'b1;
            end

            // Occupancy level counter in read domain
            if (fifo_wr_en && !fifo_rd_en) begin
                if (rd_occupancy < FIFO_DEPTH)
                    rd_occupancy <= rd_occupancy + 1'b1;
            end else if (!fifo_wr_en && fifo_rd_en) begin
                if (rd_occupancy > 0)
                    rd_occupancy <= rd_occupancy - 1'b1;
            end
        end
    end

    // Write domain approximate occupancy counter
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_occupancy <= 16'd0;
        end else if (ctrl_soft_reset) begin
            wr_occupancy <= 16'd0;
        end else begin
            if (fifo_wr_en && !fifo_rd_en) begin
                if (wr_occupancy < FIFO_DEPTH)
                    wr_occupancy <= wr_occupancy + 1'b1;
            end else if (!fifo_wr_en && fifo_rd_en) begin
                if (wr_occupancy > 0)
                    wr_occupancy <= wr_occupancy - 1'b1;
            end
        end
    end

    assign almost_full  = (rd_occupancy >= almost_full_thresh);
    assign almost_empty = (rd_occupancy <= almost_empty_thresh);

    // ------------------------------------------------------------------------
    // CDC Pulse Synchronizer: aclk diag_clear -> wr_clk domain
    // Converts a 1-cycle pulse in aclk into a 1-cycle pulse in wr_clk.
    // Uses toggle-flip-flop method for reliable single-shot crossing.
    // Declared here so wr_diag_clear_sync is available for the instantiation below.
    // ------------------------------------------------------------------------
    wire        wr_clr_req  = (diag_clear[0] || diag_clear[2] || diag_clear[4]);

    reg         wr_clr_tog;         // Toggle FF in aclk
    reg [1:0]   wr_clr_sync;        // 2-stage sync in wr_clk
    reg         wr_clr_sync_prev;   // Edge detect in wr_clk

    // Toggle in source domain (aclk) on every clear request
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) wr_clr_tog <= 1'b0;
        else if (wr_clr_req) wr_clr_tog <= ~wr_clr_tog;
    end

    // Synchronize toggle into wr_clk
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_clr_sync      <= 2'b00;
            wr_clr_sync_prev <= 1'b0;
        end else begin
            wr_clr_sync      <= {wr_clr_sync[0], wr_clr_tog};
            wr_clr_sync_prev <= wr_clr_sync[1];
        end
    end

    // Generate 1-cycle pulse in wr_clk on each toggle edge
    wire wr_diag_clear_sync = wr_clr_sync[1] ^ wr_clr_sync_prev;

    // ------------------------------------------------------------------------
    // Core Asynchronous FIFO Instance (async_fifo_top)
    // ------------------------------------------------------------------------
    async_fifo_top #(
        .DATA_WIDTH  (PAYLOAD_WIDTH), // 37 bits: {tlast, tkeep, tdata}
        .DEPTH       (FIFO_DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_async_fifo_core (
        // Write Side Interface
        .wr_clk              (wr_clk),
        .wr_rst_n            (wr_rst_n && !ctrl_soft_reset),
        .wr_en               (fifo_wr_en),
        .wr_data             (fifo_wr_payload),
        .wr_full             (core_wr_full),
        .wr_overflow         (core_wr_overflow),

        // Read Side Interface
        .rd_clk              (aclk),
        .rd_rst_n            (aresetn && !ctrl_soft_reset),
        .rd_en               (fifo_rd_en),
        .rd_data             (fifo_rd_payload),
        .rd_empty            (core_rd_empty),
        .rd_valid            (core_rd_valid),
        .rd_underflow        (core_rd_underflow),

        // Write Diagnostics (clear crosses to wr_clk domain via pulse sync)
        .wr_diag_clear       (wr_diag_clear_sync),
        .wr_gray_error       (wr_gray_error),
        .wr_overflow_sticky  (wr_overflow_sticky),
        .wr_pointer_stuck    (wr_pointer_stuck),

        // Read Diagnostics (stays in aclk domain)
        .rd_diag_clear       (|diag_clear[5:0]),
        .rd_gray_error       (rd_gray_error),
        .rd_underflow_sticky (rd_underflow_sticky),
        .rd_pointer_stuck    (rd_pointer_stuck)
    );

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Register Interface Instance
    // ------------------------------------------------------------------------
    fifo_axi4lite_slave #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) u_axi4lite_slave (
        .aclk                   (aclk),
        .aresetn                (aresetn),

        // AXI4-Lite Interface
        .s_axi_awaddr           (s_axi_awaddr),
        .s_axi_awprot           (s_axi_awprot),
        .s_axi_awvalid          (s_axi_awvalid),
        .s_axi_awready          (s_axi_awready),

        .s_axi_wdata            (s_axi_wdata),
        .s_axi_wstrb            (s_axi_wstrb),
        .s_axi_wvalid           (s_axi_wvalid),
        .s_axi_wready           (s_axi_wready),

        .s_axi_bresp            (s_axi_bresp),
        .s_axi_bvalid           (s_axi_bvalid),
        .s_axi_bready           (s_axi_bready),

        .s_axi_araddr           (s_axi_araddr),
        .s_axi_arprot           (s_axi_arprot),
        .s_axi_arvalid          (s_axi_arvalid),
        .s_axi_arready          (s_axi_arready),

        .s_axi_rdata            (s_axi_rdata),
        .s_axi_rresp            (s_axi_rresp),
        .s_axi_rvalid           (s_axi_rvalid),
        .s_axi_rready           (s_axi_rready),

        // CPU Direct Data Ports
        .cpu_wr_en_o            (cpu_wr_en),
        .cpu_wr_data_o          (cpu_wr_data),
        .cpu_wr_be_o            (cpu_wr_be),
        .cpu_wr_last_o          (cpu_wr_last),

        .cpu_rd_en_o            (cpu_rd_en),
        .cpu_rd_data_i          (cpu_rd_data),
        .cpu_rd_valid_i         (cpu_rd_valid),

        // Control Signals
        .ctrl_enable_o          (ctrl_enable),
        .ctrl_soft_reset_o      (ctrl_soft_reset),
        .ctrl_stream_en_o       (ctrl_stream_en),
        .almost_full_thresh_o   (almost_full_thresh),
        .almost_empty_thresh_o  (almost_empty_thresh),
        .diag_clear_o           (diag_clear),

        // Status Inputs
        .wr_full_i              (core_wr_full),
        .rd_empty_i             (core_rd_empty),
        .wr_overflow_i          (core_wr_overflow),
        .rd_underflow_i         (core_rd_underflow),
        .stream_active_i        (stream_active),
        .almost_full_i          (almost_full),
        .almost_empty_i         (almost_empty),

        // Diagnostic Inputs
        .diag_wr_gray_err_i     (aclk_wr_gray_error),
        .diag_rd_gray_err_i     (rd_gray_error),
        .diag_wr_ovf_sticky_i   (aclk_wr_overflow_sticky),
        .diag_rd_unf_sticky_i   (rd_underflow_sticky),
        .diag_wr_stuck_i        (aclk_wr_pointer_stuck),
        .diag_rd_stuck_i        (rd_pointer_stuck),

        // Occupancy & Counters
        .wr_occupancy_i         (wr_occupancy),
        .rd_occupancy_i         (rd_occupancy),
        .packet_count_i         (packet_count),

        // Interrupt Request
        .irq_o                  (fifo_irq_o)
    );

endmodule
`default_nettype wire
