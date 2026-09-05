`timescale 1ns/1ps
`default_nettype none

//======================================================================
// GENERIC AXI4 MASTER
//
// Purpose:
//   Generates AXI4 transactions for the AES project.
//   One write burst and one read burst may be active independently.
//
// High-level WRITE interface:
//   Present wr_cmd_* and assert wr_cmd_valid.
//   Wait for wr_cmd_ready.
//   Then provide one data beat whenever wr_data_ready is asserted.
//   Keep wr_data_valid/data/last stable until accepted.
//
// High-level READ interface:
//   Present rd_cmd_* and assert rd_cmd_valid.
//   Wait for rd_cmd_ready.
//   Returned AXI R-channel beats appear on rd_data_valid.
//   rd_data_last marks the final beat.
//
// AXI data width: 32 bits by default
// AXI address width: 32 bits by default
// AXI ID width: 8 bits by default
//
// Supports:
//   - AXI AW, W, B, AR, R channels
//   - FIXED, INCR, WRAP bursts
//   - 1 to 256 beats per burst
//   - WSTRB
//   - WLAST / RLAST
//   - AXI IDs
//   - independent read/write operation
//
//======================================================================

module axi_master #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter STRB_WIDTH   = DATA_WIDTH/8,
    parameter ID_WIDTH     = 8,
    parameter AWUSER_WIDTH = 1,
    parameter WUSER_WIDTH  = 1,
    parameter BUSER_WIDTH  = 1,
    parameter ARUSER_WIDTH = 1,
    parameter RUSER_WIDTH  = 1
)(
    input  wire                     clk,
    input  wire                     rst,

    //==================================================================
    // High-level WRITE COMMAND interface
    //==================================================================
    input  wire                     wr_cmd_valid,
    output wire                     wr_cmd_ready,

    input  wire [ID_WIDTH-1:0]      wr_cmd_id,
    input  wire [ADDR_WIDTH-1:0]    wr_cmd_addr,
    input  wire [7:0]               wr_cmd_len,       // beats - 1
    input  wire [2:0]               wr_cmd_size,      // log2(bytes/beat)
    input  wire [1:0]               wr_cmd_burst,

    // Write data stream
    input  wire                     wr_data_valid,
    output wire                     wr_data_ready,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    input  wire [STRB_WIDTH-1:0]    wr_strb,
    input  wire                     wr_data_last,

    // Write completion
    output reg                      wr_done,
    output reg  [1:0]               wr_resp,

    //==================================================================
    // High-level READ COMMAND interface
    //==================================================================
    input  wire                     rd_cmd_valid,
    output wire                     rd_cmd_ready,

    input  wire [ID_WIDTH-1:0]      rd_cmd_id,
    input  wire [ADDR_WIDTH-1:0]    rd_cmd_addr,
    input  wire [7:0]               rd_cmd_len,       // beats - 1
    input  wire [2:0]               rd_cmd_size,      // log2(bytes/beat)
    input  wire [1:0]               rd_cmd_burst,

    // Read data stream
    output reg                      rd_data_valid,
    input  wire                     rd_data_ready,
    output reg  [DATA_WIDTH-1:0]    rd_data,
    output reg  [ID_WIDTH-1:0]      rd_data_id,
    output reg  [1:0]               rd_data_resp,
    output reg                      rd_data_last,

    // Read completion
    output reg                      rd_done,
    output reg  [1:0]               rd_resp,

    //==================================================================
    // AXI4 MASTER WRITE ADDRESS CHANNEL
    //==================================================================
    output reg  [ID_WIDTH-1:0]      m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output reg  [2:0]               m_axi_awsize,
    output reg  [1:0]               m_axi_awburst,
    output reg                      m_axi_awlock,
    output reg  [3:0]               m_axi_awcache,
    output reg  [2:0]               m_axi_awprot,
    output reg  [3:0]               m_axi_awqos,
    output reg  [3:0]               m_axi_awregion,
    output reg  [AWUSER_WIDTH-1:0]  m_axi_awuser,
    output reg                      m_axi_awvalid,
    input  wire                      m_axi_awready,

    //==================================================================
    // AXI4 MASTER WRITE DATA CHANNEL
    //==================================================================
    output reg  [DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [STRB_WIDTH-1:0]    m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg  [WUSER_WIDTH-1:0]   m_axi_wuser,
    output reg                      m_axi_wvalid,
    input  wire                      m_axi_wready,

    //==================================================================
    // AXI4 MASTER WRITE RESPONSE CHANNEL
    //==================================================================
    input  wire [ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]   m_axi_buser,
    input  wire                      m_axi_bvalid,
    output wire                     m_axi_bready,

    //==================================================================
    // AXI4 MASTER READ ADDRESS CHANNEL
    //==================================================================
    output reg  [ID_WIDTH-1:0]      m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output reg  [2:0]               m_axi_arsize,
    output reg  [1:0]               m_axi_arburst,
    output reg                      m_axi_arlock,
    output reg  [3:0]               m_axi_arcache,
    output reg  [2:0]               m_axi_arprot,
    output reg  [3:0]               m_axi_arqos,
    output reg  [3:0]               m_axi_arregion,
    output reg  [ARUSER_WIDTH-1:0]  m_axi_aruser,
    output reg                      m_axi_arvalid,
    input  wire                      m_axi_arready,

    //==================================================================
    // AXI4 MASTER READ DATA CHANNEL
    //==================================================================
    input  wire [ID_WIDTH-1:0]      m_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                      m_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]   m_axi_ruser,
    input  wire                      m_axi_rvalid,
    output wire                     m_axi_rready
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;

    localparam integer DATA_BYTES = DATA_WIDTH/8;
    localparam integer MAX_SIZE   = $clog2(DATA_BYTES);

    //==================================================================
    // WRITE state
    //==================================================================

    localparam [1:0] WR_IDLE = 2'd0;
    localparam [1:0] WR_ADDR = 2'd1;
    localparam [1:0] WR_DATA = 2'd2;
    localparam [1:0] WR_RESP = 2'd3;

    reg [1:0]            wr_state;

    reg [ID_WIDTH-1:0]  wr_id_reg;
    reg [ADDR_WIDTH-1:0] wr_addr_reg;
    reg [ADDR_WIDTH-1:0] wr_start_addr_reg;
    reg [7:0]            wr_len_reg;
    reg [2:0]            wr_size_reg;
    reg [1:0]            wr_burst_reg;
    reg [7:0]            wr_beat_reg;
    reg                  wr_error_reg;

    //==================================================================
    // READ state
    //==================================================================

    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_ADDR = 2'd1;
    localparam [1:0] RD_DATA = 2'd2;
    localparam [1:0] RD_DONE = 2'd3;

    reg [1:0]             rd_state;

    reg [ID_WIDTH-1:0]   rd_id_reg;
    reg [ADDR_WIDTH-1:0] rd_addr_reg;
    reg [ADDR_WIDTH-1:0] rd_start_addr_reg;
    reg [7:0]             rd_len_reg;
    reg [2:0]             rd_size_reg;
    reg [1:0]             rd_burst_reg;
    reg [7:0]             rd_beat_reg;
    reg                   rd_error_reg;

    //==================================================================
    // Command ready
    //==================================================================

    assign wr_cmd_ready = (wr_state == WR_IDLE);
    assign rd_cmd_ready = (rd_state == RD_IDLE);

    // W data is accepted only after AW has completed.
    assign wr_data_ready = (wr_state == WR_DATA) &&
                           m_axi_wready &&
                           !m_axi_bvalid;

    // AXI response/data channels are consumed whenever the corresponding
    // transaction is in its response/data state.
    assign m_axi_bready = (wr_state == WR_RESP);
    assign m_axi_rready = (rd_state == RD_DATA) && !rd_data_valid;

    //==================================================================
    // Burst address calculation
    //==================================================================

    function [ADDR_WIDTH-1:0] next_burst_addr;
        input [ADDR_WIDTH-1:0] current_addr;
        input [ADDR_WIDTH-1:0] start_addr;
        input [7:0]            len;
        input [2:0]            size;
        input [1:0]            burst;

        reg [ADDR_WIDTH-1:0] beat_bytes;
        reg [ADDR_WIDTH-1:0] wrap_bytes;
        reg [ADDR_WIDTH-1:0] wrap_base;
        reg [ADDR_WIDTH-1:0] incr_addr;

        begin
            beat_bytes = {{(ADDR_WIDTH-1){1'b0}},1'b1} << size;
            incr_addr  = current_addr + beat_bytes;

            case (burst)

                BURST_FIXED:
                    next_burst_addr = current_addr;

                BURST_INCR:
                    next_burst_addr = incr_addr;

                BURST_WRAP: begin
                    wrap_bytes = ({{(ADDR_WIDTH-8){1'b0}},len} + 1'b1)
                                 << size;

                    wrap_base = start_addr & ~(wrap_bytes - 1'b1);

                    if (incr_addr >= (wrap_base + wrap_bytes))
                        next_burst_addr = wrap_base;
                    else
                        next_burst_addr = incr_addr;
                end

                default:
                    next_burst_addr = current_addr;

            endcase
        end
    endfunction

    //==================================================================
    // WRITE outputs
    //==================================================================

    always @(*) begin

        m_axi_awid     = wr_id_reg;
        m_axi_awaddr   = wr_addr_reg;
        m_axi_awlen    = wr_len_reg;
        m_axi_awsize   = wr_size_reg;
        m_axi_awburst  = wr_burst_reg;
        m_axi_awlock   = 1'b0;
        m_axi_awcache  = 4'b0011;
        m_axi_awprot   = 3'b000;
        m_axi_awqos    = 4'b0000;
        m_axi_awregion = 4'b0000;
        m_axi_awuser   = {AWUSER_WIDTH{1'b0}};

        m_axi_awvalid = (wr_state == WR_ADDR);

        m_axi_wdata   = {DATA_WIDTH{1'b0}};
        m_axi_wstrb   = {STRB_WIDTH{1'b0}};
        m_axi_wlast   = 1'b0;
    
    	m_axi_wuser   = {WUSER_WIDTH{1'b0}};
        m_axi_wvalid = (wr_state == WR_DATA);

        if (wr_state == WR_DATA) begin
            m_axi_wdata = wr_data;
            m_axi_wstrb = wr_strb;

            // Protocol correctness is based on the programmed burst length.
            m_axi_wlast = (wr_beat_reg == wr_len_reg);
        end

    end

    //==================================================================
    // READ outputs
    //==================================================================

    always @(*) begin

        m_axi_arid     = rd_id_reg;
        m_axi_araddr   = rd_addr_reg;
        m_axi_arlen    = rd_len_reg;
        m_axi_arsize   = rd_size_reg;
        m_axi_arburst  = rd_burst_reg;
        m_axi_arlock   = 1'b0;
        m_axi_arcache  = 4'b0011;
        m_axi_arprot   = 3'b000;
        m_axi_arqos    = 4'b0000;
        m_axi_arregion = 4'b0000;
        m_axi_aruser   = {ARUSER_WIDTH{1'b0}};

        m_axi_arvalid = (rd_state == RD_ADDR);

    end

    //==================================================================
    // WRITE FSM
    //==================================================================

    always @(posedge clk) begin

        if (rst) begin

            wr_state        <= WR_IDLE;

            wr_id_reg       <= {ID_WIDTH{1'b0}};
            wr_addr_reg     <= {ADDR_WIDTH{1'b0}};
            wr_start_addr_reg <= {ADDR_WIDTH{1'b0}};
            wr_len_reg      <= 8'd0;
            wr_size_reg     <= 3'd0;
            wr_burst_reg    <= BURST_INCR;
            wr_beat_reg     <= 8'd0;
            wr_error_reg    <= 1'b0;

            wr_done         <= 1'b0;
            wr_resp         <= RESP_OKAY;


        end else begin

            wr_done      <= 1'b0;

            case (wr_state)

                //======================================================
                WR_IDLE:
                //======================================================
                begin
                    if (wr_cmd_valid && wr_cmd_ready) begin

                        wr_id_reg         <= wr_cmd_id;
                        wr_addr_reg       <= wr_cmd_addr;
                        wr_start_addr_reg <= wr_cmd_addr;
                        wr_len_reg        <= wr_cmd_len;
                        wr_size_reg       <= wr_cmd_size;
                        wr_burst_reg      <= wr_cmd_burst;
                        wr_beat_reg       <= 8'd0;

                        wr_error_reg <= (wr_cmd_size > MAX_SIZE) ||
                                        (wr_cmd_burst == 2'b11);

                        wr_state <= WR_ADDR;

                    end
                end

                //======================================================
                WR_ADDR:
                //======================================================
                begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        wr_state <= WR_DATA;
                    end
                end

                //======================================================
                WR_DATA:
                //======================================================
                begin

                    if (wr_data_valid && wr_data_ready) begin

                        // Check user supplied last against programmed
                        // burst length.
                        if (wr_data_last != (wr_beat_reg == wr_len_reg))
                            wr_error_reg <= 1'b1;

                        // Advance to next beat.
                        if (wr_beat_reg == wr_len_reg) begin
                            wr_state <= WR_RESP;
                        end else begin
                            wr_beat_reg <= wr_beat_reg + 1'b1;

                            wr_addr_reg <= next_burst_addr(
                                wr_addr_reg,
                                wr_start_addr_reg,
                                wr_len_reg,
                                wr_size_reg,
                                wr_burst_reg
                            );
                        end
                    end

                end

                //======================================================
                WR_RESP:
                //======================================================
                begin

                    if (m_axi_bvalid) begin

                        if (m_axi_bvalid && m_axi_bready) begin

                            wr_resp <= wr_error_reg
                                       ? RESP_SLVERR
                                       : m_axi_bresp;

                            wr_done  <= 1'b1;
                            wr_state <= WR_IDLE;

                        end
                    end

                end

                default:
                    wr_state <= WR_IDLE;

            endcase

        end

    end

    //==================================================================
    // READ FSM
    //==================================================================

    always @(posedge clk) begin

        if (rst) begin

            rd_state          <= RD_IDLE;

            rd_id_reg         <= {ID_WIDTH{1'b0}};
            rd_addr_reg       <= {ADDR_WIDTH{1'b0}};
            rd_start_addr_reg <= {ADDR_WIDTH{1'b0}};
            rd_len_reg        <= 8'd0;
            rd_size_reg       <= 3'd0;
            rd_burst_reg      <= BURST_INCR;
            rd_beat_reg       <= 8'd0;
            rd_error_reg      <= 1'b0;

            rd_data_valid     <= 1'b0;
            rd_data           <= {DATA_WIDTH{1'b0}};
            rd_data_id       <= {ID_WIDTH{1'b0}};
            rd_data_resp      <= RESP_OKAY;
            rd_data_last      <= 1'b0;

            rd_done           <= 1'b0;
            rd_resp           <= RESP_OKAY;


        end else begin

            rd_done      <= 1'b0;

            // rd_data_valid is held until the consumer accepts it.
            if (rd_data_valid && rd_data_ready) begin
                rd_data_valid <= 1'b0;
            end

            case (rd_state)

                //======================================================
                RD_IDLE:
                //======================================================
                begin
                    if (rd_cmd_valid && rd_cmd_ready) begin

                        rd_id_reg         <= rd_cmd_id;
                        rd_addr_reg       <= rd_cmd_addr;
                        rd_start_addr_reg <= rd_cmd_addr;
                        rd_len_reg        <= rd_cmd_len;
                        rd_size_reg       <= rd_cmd_size;
                        rd_burst_reg      <= rd_cmd_burst;
                        rd_beat_reg       <= 8'd0;

                        rd_error_reg <= (rd_cmd_size > MAX_SIZE) ||
                                        (rd_cmd_burst == 2'b11);

                        rd_state <= RD_ADDR;

                    end
                end

                //======================================================
                RD_ADDR:
                //======================================================
                begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        rd_state <= RD_DATA;
                    end
                end

                //======================================================
                RD_DATA:
                //======================================================
                begin

                    // One output register provides back-pressure to AXI.
                    if (!rd_data_valid) begin

                        if (m_axi_rvalid && m_axi_rready) begin

                            rd_data_valid <= 1'b1;
                            rd_data        <= m_axi_rdata;
                            rd_data_id     <= m_axi_rid;
                            rd_data_resp   <= m_axi_rresp;

                            rd_data_last <= (rd_beat_reg == rd_len_reg) ||
                                            m_axi_rlast;

                            if (m_axi_rresp != RESP_OKAY)
                                rd_error_reg <= 1'b1;

                            if ((rd_beat_reg == rd_len_reg) ||
                                m_axi_rlast) begin

                                rd_state <= RD_DONE;

                            end else begin

                                rd_beat_reg <= rd_beat_reg + 1'b1;

                                rd_addr_reg <= next_burst_addr(
                                    rd_addr_reg,
                                    rd_start_addr_reg,
                                    rd_len_reg,
                                    rd_size_reg,
                                    rd_burst_reg
                                );

                            end

                        end
                    end

                end

                //======================================================
                RD_DONE:
                //======================================================
                begin

                    if (!rd_data_valid || rd_data_ready) begin

                        rd_resp <= rd_error_reg
                                   ? RESP_SLVERR
                                   : RESP_OKAY;

                        rd_done  <= 1'b1;
                        rd_state <= RD_IDLE;

                    end

                end

                default:
                    rd_state <= RD_IDLE;

            endcase

        end

    end

endmodule

`default_nettype wire
