/*
 * ============================================================================
 * File: fifo_axi4lite_slave.v
 * Project: Reliable Data Transport System SoC
 * Description: AXI4-Lite Slave Register Interface for the Packet FIFO IP.
 *              Maps configuration, control, status, CDC diagnostic flags,
 *              and CPU direct data ports into the 4 KB region allocated at 0x0007_0000.
 * ============================================================================
 */

// timescale defined via compiler flag -timescale=1ns/1ps

`include "fifo_defines.vh"

module fifo_axi4lite_slave #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32
)(
    input  wire                          aclk,
    input  wire                          aresetn,

    // AXI4-Lite Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                    s_axi_awprot,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                    s_axi_arprot,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // CPU Direct Write Port to FIFO
    output reg                           cpu_wr_en_o,
    output reg  [31:0]                   cpu_wr_data_o,
    output reg  [3:0]                    cpu_wr_be_o,
    output reg                           cpu_wr_last_o,

    // CPU Direct Read Port from FIFO
    output reg                           cpu_rd_en_o,
    input  wire [31:0]                   cpu_rd_data_i,
    input  wire                          cpu_rd_valid_i,

    // Internal Control Signals
    output wire                          ctrl_enable_o,
    output reg                           ctrl_soft_reset_o,
    output wire                          ctrl_stream_en_o,
    output reg  [15:0]                   almost_full_thresh_o,
    output reg  [15:0]                   almost_empty_thresh_o,
    output reg  [5:0]                    diag_clear_o,

    // Status Inputs from FIFO Core
    input  wire                          wr_full_i,
    input  wire                          rd_empty_i,
    input  wire                          wr_overflow_i,
    input  wire                          rd_underflow_i,
    input  wire                          stream_active_i,
    input  wire                          almost_full_i,
    input  wire                          almost_empty_i,

    // Diagnostic Inputs from fifo_diag
    input  wire                          diag_wr_gray_err_i,
    input  wire                          diag_rd_gray_err_i,
    input  wire                          diag_wr_ovf_sticky_i,
    input  wire                          diag_rd_unf_sticky_i,
    input  wire                          diag_wr_stuck_i,
    input  wire                          diag_rd_stuck_i,

    // Occupancy and Statistics Inputs
    input  wire [15:0]                   wr_occupancy_i,
    input  wire [15:0]                   rd_occupancy_i,
    input  wire [31:0]                   packet_count_i,

    // Interrupt Request Output to SoC PIC
    output wire                          irq_o
);

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    reg [31:0] reg_ctrl;
    reg [31:0] reg_threshold;

    // Sticky error shadow registers with W1C support
    reg reg_wr_gray_err_latched;
    reg reg_rd_gray_err_latched;
    reg reg_wr_ovf_sticky_latched;
    reg reg_rd_unf_sticky_latched;
    reg reg_wr_stuck_latched;
    reg reg_rd_stuck_latched;

    // Control wire decodes
    assign ctrl_enable_o    = reg_ctrl[`FIFO_CTRL_ENABLE_BIT];
    assign ctrl_stream_en_o = reg_ctrl[`FIFO_CTRL_STREAM_EN_BIT];

    // Interrupt enables
    wire ie_overflow    = reg_ctrl[`FIFO_CTRL_IE_OVERFLOW_BIT];
    wire ie_underflow   = reg_ctrl[`FIFO_CTRL_IE_UNDERFLOW_BIT];
    wire ie_cdc_error   = reg_ctrl[`FIFO_CTRL_IE_CDC_ERROR_BIT];
    wire ie_almost_full = reg_ctrl[`FIFO_CTRL_IE_ALMOST_FULL_BIT];
    wire ie_data_avail  = reg_ctrl[`FIFO_CTRL_IE_DATA_AVAIL_BIT];

    // Interrupt source conditions
    wire irq_overflow  = ie_overflow && (wr_overflow_i || reg_wr_ovf_sticky_latched);
    wire irq_underflow = ie_underflow && (rd_underflow_i || reg_rd_unf_sticky_latched);
    wire irq_cdc       = ie_cdc_error && (reg_wr_gray_err_latched || reg_rd_gray_err_latched ||
                                          reg_wr_stuck_latched || reg_rd_stuck_latched);
    wire irq_afull     = ie_almost_full && almost_full_i;
    wire irq_davail    = ie_data_avail && !rd_empty_i;

    assign irq_o = ctrl_enable_o && (irq_overflow || irq_underflow || irq_cdc || irq_afull || irq_davail);

    // Status word construction
    wire [31:0] status_word = {
        24'd0,
        irq_o,
        stream_active_i,
        almost_empty_i,
        almost_full_i,
        rd_underflow_i,
        wr_overflow_i,
        rd_empty_i,
        wr_full_i
    };

    // Diagnostic status word construction
    wire [31:0] diag_status_word = {
        26'd0,
        reg_rd_stuck_latched,
        reg_wr_stuck_latched,
        reg_rd_unf_sticky_latched,
        reg_wr_ovf_sticky_latched,
        reg_rd_gray_err_latched,
        reg_wr_gray_err_latched
    };

    // ------------------------------------------------------------------------
    // Edge detectors for write-domain diagnostic inputs.
    // The wr_overflow_sticky and wr_pointer_stuck signals are level signals
    // that are synchronised into aclk by a 2-stage synchroniser.  When a W1C
    // clear is performed the local latch is cleared in one cycle, but the
    // synchronised level stays high for ~2+ more aclk cycles while the clear
    // CDC-path propagates through wr_clk and back.  Sampling the level would
    // immediately re-set the latch.  Instead, only SET the latch on a RISING
    // EDGE of the synchronised input so that a new event is required.
    // ------------------------------------------------------------------------
    reg diag_wr_gray_err_d;
    reg diag_wr_ovf_sticky_d;
    reg diag_wr_stuck_d;
    reg diag_rd_gray_err_d;
    reg diag_rd_unf_sticky_d;
    reg diag_rd_stuck_d;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            diag_wr_gray_err_d    <= 1'b0;
            diag_wr_ovf_sticky_d  <= 1'b0;
            diag_wr_stuck_d       <= 1'b0;
            diag_rd_gray_err_d    <= 1'b0;
            diag_rd_unf_sticky_d  <= 1'b0;
            diag_rd_stuck_d       <= 1'b0;
        end else begin
            diag_wr_gray_err_d    <= diag_wr_gray_err_i;
            diag_wr_ovf_sticky_d  <= diag_wr_ovf_sticky_i;
            diag_wr_stuck_d       <= diag_wr_stuck_i;
            diag_rd_gray_err_d    <= diag_rd_gray_err_i;
            diag_rd_unf_sticky_d  <= diag_rd_unf_sticky_i;
            diag_rd_stuck_d       <= diag_rd_stuck_i;
        end
    end

    // Rising-edge pulses: set latch only when the input newly asserts
    wire diag_wr_gray_err_re   = diag_wr_gray_err_i   && !diag_wr_gray_err_d;
    wire diag_wr_ovf_sticky_re = diag_wr_ovf_sticky_i && !diag_wr_ovf_sticky_d;
    wire diag_wr_stuck_re      = diag_wr_stuck_i      && !diag_wr_stuck_d;
    wire diag_rd_gray_err_re   = diag_rd_gray_err_i   && !diag_rd_gray_err_d;
    wire diag_rd_unf_sticky_re = diag_rd_unf_sticky_i && !diag_rd_unf_sticky_d;
    wire diag_rd_stuck_re      = diag_rd_stuck_i      && !diag_rd_stuck_d;

    // ------------------------------------------------------------------------
    // Latch CDC Diagnostics from core
    // W1C clear has strict priority.  The latch sets only on a rising edge of
    // the synchronised input so a W1C clear cannot be immediately overridden
    // by the still-asserted level before the remote sticky register clears.
    // ------------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            reg_wr_gray_err_latched   <= 1'b0;
            reg_rd_gray_err_latched   <= 1'b0;
            reg_wr_ovf_sticky_latched <= 1'b0;
            reg_rd_unf_sticky_latched <= 1'b0;
            reg_wr_stuck_latched      <= 1'b0;
            reg_rd_stuck_latched      <= 1'b0;
        end else begin
            if      (diag_clear_o[0]) reg_wr_gray_err_latched   <= 1'b0;
            else if (diag_wr_gray_err_re) reg_wr_gray_err_latched <= 1'b1;

            if      (diag_clear_o[1]) reg_rd_gray_err_latched   <= 1'b0;
            else if (diag_rd_gray_err_re) reg_rd_gray_err_latched <= 1'b1;

            if      (diag_clear_o[2]) reg_wr_ovf_sticky_latched <= 1'b0;
            else if (diag_wr_ovf_sticky_re) reg_wr_ovf_sticky_latched <= 1'b1;

            if      (diag_clear_o[3]) reg_rd_unf_sticky_latched <= 1'b0;
            else if (diag_rd_unf_sticky_re) reg_rd_unf_sticky_latched <= 1'b1;

            if      (diag_clear_o[4]) reg_wr_stuck_latched      <= 1'b0;
            else if (diag_wr_stuck_re) reg_wr_stuck_latched      <= 1'b1;

            if      (diag_clear_o[5]) reg_rd_stuck_latched      <= 1'b0;
            else if (diag_rd_stuck_re) reg_rd_stuck_latched      <= 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // AXI4-Lite Write Transaction Handling
    // ------------------------------------------------------------------------
    reg [AXI_ADDR_WIDTH-1:0] awaddr_latched;
    reg write_in_progress;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_awready        <= 1'b0;
            s_axi_wready         <= 1'b0;
            s_axi_bvalid         <= 1'b0;
            s_axi_bresp          <= 2'b00;
            write_in_progress    <= 1'b0;
            awaddr_latched       <= {AXI_ADDR_WIDTH{1'b0}};

            reg_ctrl             <= `FIFO_DEFAULT_CTRL;
            reg_threshold        <= 32'h000E_0002; // almost full=14, almost empty=2
            almost_full_thresh_o <= 16'd14;
            almost_empty_thresh_o<= 16'd2;
            ctrl_soft_reset_o    <= 1'b0;
            diag_clear_o         <= 6'd0;

            cpu_wr_en_o          <= 1'b0;
            cpu_wr_data_o        <= 32'd0;
            cpu_wr_be_o          <= 4'd0;
            cpu_wr_last_o        <= 1'b0;
        end else begin
            // Single-cycle control pulses
            ctrl_soft_reset_o <= 1'b0;
            diag_clear_o      <= 6'd0;
            cpu_wr_en_o       <= 1'b0;

            // Step 1: Handshake write address & write data
            if (!write_in_progress) begin
                if (s_axi_awvalid && s_axi_wvalid) begin
                    s_axi_awready     <= 1'b1;
                    s_axi_wready      <= 1'b1;
                    awaddr_latched    <= s_axi_awaddr;
                    write_in_progress <= 1'b1;

                    // Execute register write
                    case (s_axi_awaddr[5:0])
                        `FIFO_REG_DATA: begin
                            cpu_wr_en_o   <= 1'b1;
                            cpu_wr_data_o <= s_axi_wdata;
                            cpu_wr_be_o   <= s_axi_wstrb;
                            cpu_wr_last_o <= 1'b0;
                        end

                        `FIFO_REG_DATA_LAST: begin
                            cpu_wr_en_o   <= 1'b1;
                            cpu_wr_data_o <= s_axi_wdata;
                            cpu_wr_be_o   <= s_axi_wstrb;
                            cpu_wr_last_o <= 1'b1;
                        end

                        `FIFO_REG_CTRL: begin
                            reg_ctrl          <= s_axi_wdata;
                            ctrl_soft_reset_o <= s_axi_wdata[`FIFO_CTRL_SOFT_RESET_BIT];
                        end

                        `FIFO_REG_DIAG_STATUS: begin
                            diag_clear_o <= s_axi_wdata[5:0];
                        end

                        `FIFO_REG_THRESHOLD: begin
                            reg_threshold         <= s_axi_wdata;
                            almost_empty_thresh_o <= s_axi_wdata[15:0];
                            almost_full_thresh_o  <= s_axi_wdata[31:16];
                        end

                        default: ; // Ignore writes to read-only or reserved offsets
                    endcase
                end
            end else begin
                // Step 2: Complete write response
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00; // OKAY

                if (s_axi_bvalid && s_axi_bready) begin
                    s_axi_bvalid      <= 1'b0;
                    write_in_progress <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // AXI4-Lite Read Transaction Handling
    // ------------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
            cpu_rd_en_o   <= 1'b0;
        end else begin
            cpu_rd_en_o <= 1'b0;

            if (!s_axi_rvalid) begin
                if (s_axi_arvalid) begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b1;
                    s_axi_rresp   <= 2'b00; // OKAY

                    case (s_axi_araddr[5:0])
                        `FIFO_REG_DATA: begin
                            s_axi_rdata <= cpu_rd_data_i;
                            cpu_rd_en_o <= 1'b1; // Pop word on direct CPU read
                        end

                        `FIFO_REG_STATUS: begin
                            s_axi_rdata <= status_word;
                        end

                        `FIFO_REG_CTRL: begin
                            s_axi_rdata <= reg_ctrl;
                        end

                        `FIFO_REG_DIAG_STATUS: begin
                            s_axi_rdata <= diag_status_word;
                        end

                        `FIFO_REG_OCCUPANCY: begin
                            s_axi_rdata <= {rd_occupancy_i, wr_occupancy_i};
                        end

                        `FIFO_REG_THRESHOLD: begin
                            s_axi_rdata <= reg_threshold;
                        end

                        `FIFO_REG_PACKET_COUNT: begin
                            s_axi_rdata <= packet_count_i;
                        end

                        default: begin
                            s_axi_rdata <= 32'h0000_0000;
                        end
                    endcase
                end
            end else begin
                s_axi_arready <= 1'b0;
                if (s_axi_rready) begin
                    s_axi_rvalid <= 1'b0;
                end
            end
        end
    end

endmodule
`default_nettype wire
