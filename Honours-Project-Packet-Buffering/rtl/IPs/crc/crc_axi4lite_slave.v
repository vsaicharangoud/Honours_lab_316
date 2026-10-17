/*
 * ============================================================================
 * File: crc_axi4lite_slave.v
 * Project: Reliable Data Transport System SoC
 * Description: AXI4-Lite Slave Register Interface for the CRC-32 IP Core.
 *              Maps configuration, status, results, and manual data registers
 *              into the 4 KB region allocated at 0x000A_0000.
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "crc_defines.vh"

module crc_axi4lite_slave #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32
)(
    input  wire                      aclk,
    input  wire                      aresetn,

    // AXI4-Lite Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]                s_axi_awprot,
    input  wire                      s_axi_awvalid,
    output reg                       s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output reg                       s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]                s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                s_axi_arprot,
    input  wire                      s_axi_arvalid,
    output reg                       s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]                s_axi_rresp,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready,

    // Internal Control Signals to CRC Checker / Engine
    output wire                      ctrl_enable_o,
    output reg                       ctrl_soft_reset_o,
    output wire                      ctrl_auto_clear_o,
    output wire [1:0]                mode_config_o,
    output reg  [31:0]               poly_rev_o,
    output reg  [31:0]               init_val_o,
    output reg  [31:0]               exp_crc_reg_o,
    output reg                       exp_crc_we_o,
    output reg                       clear_counters_o,

    // CPU Manual Injection Port
    output reg                       manual_data_valid_o,
    output reg  [3:0]                manual_data_be_o,
    output reg  [31:0]               manual_data_in_o,
    output reg                       manual_data_last_o,

    // Internal Status Inputs from CRC Checker
    input  wire                      checker_busy_i,
    input  wire                      checker_done_i,
    input  wire                      checker_pass_i,
    input  wire                      checker_error_i,
    input  wire [31:0]               calc_crc_result_i,
    input  wire [31:0]               exp_crc_result_i,
    input  wire [31:0]               byte_count_i,
    input  wire [31:0]               pass_count_i,
    input  wire [31:0]               error_count_i,

    // Interrupt Request Output to SoC
    output wire                      irq_o
);

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    reg [31:0] reg_ctrl;
    reg [31:0] reg_status;
    reg [31:0] reg_mode_config;

    // Control wire decodes
    assign ctrl_enable_o     = reg_ctrl[`CRC_CTRL_ENABLE_BIT];
    assign ctrl_auto_clear_o  = reg_ctrl[`CRC_CTRL_AUTO_CLEAR_BIT];
    assign mode_config_o     = reg_mode_config[1:0];

    wire ie_done  = reg_ctrl[`CRC_CTRL_IE_DONE_BIT];
    wire ie_error = reg_ctrl[`CRC_CTRL_IE_ERROR_BIT];

    // Interrupt logic: active when enabled condition is set
    assign irq_o = (reg_status[`CRC_STATUS_DONE_BIT]  && ie_done) ||
                   (reg_status[`CRC_STATUS_ERROR_BIT] && ie_error);

    // ------------------------------------------------------------------------
    // Address Decoding (Use local byte offsets [5:2])
    // ------------------------------------------------------------------------
    wire [5:0] awaddr_local = s_axi_awaddr[5:0];
    wire [5:0] araddr_local = s_axi_araddr[5:0];

    // ------------------------------------------------------------------------
    // AXI4-Lite Write Channel Handshake & Register Writes
    // ------------------------------------------------------------------------
    reg aw_en;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_awready        <= 1'b0;
            s_axi_wready         <= 1'b0;
            s_axi_bvalid         <= 1'b0;
            s_axi_bresp          <= 2'b00;
            aw_en                <= 1'b1;

            reg_ctrl             <= 32'h00000011; // Enable=1, AutoClear=1 by default
            reg_status           <= 32'h00000000;
            reg_mode_config      <= 32'h00000001; // Default: Register comparison mode
            poly_rev_o           <= `CRC32_DEFAULT_POLY_REV;
            init_val_o           <= `CRC32_DEFAULT_INIT;
            exp_crc_reg_o        <= 32'h00000000;
            exp_crc_we_o         <= 1'b0;
            ctrl_soft_reset_o    <= 1'b0;
            clear_counters_o     <= 1'b0;
            manual_data_valid_o  <= 1'b0;
            manual_data_be_o     <= 4'b0000;
            manual_data_in_o     <= 32'h00000000;
            manual_data_last_o   <= 1'b0;
        end else begin
            // Clear single-cycle strobes
            exp_crc_we_o         <= 1'b0;
            ctrl_soft_reset_o    <= 1'b0;
            clear_counters_o     <= 1'b0;
            manual_data_valid_o  <= 1'b0;
            manual_data_last_o   <= 1'b0;

            // Reflect live status flags from checker
            reg_status[`CRC_STATUS_BUSY_BIT] <= checker_busy_i;
            reg_status[`CRC_STATUS_IRQ_BIT]  <= irq_o;

            if (checker_done_i)  reg_status[`CRC_STATUS_DONE_BIT]  <= 1'b1;
            if (checker_pass_i)  reg_status[`CRC_STATUS_PASS_BIT]  <= 1'b1;
            if (checker_error_i) reg_status[`CRC_STATUS_ERROR_BIT] <= 1'b1;

            // AWREADY generation
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                aw_en         <= 1'b0;
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            // Write transaction execution
            if (s_axi_awready && s_axi_wready && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY


                case (awaddr_local[5:2])
                    4'h0: begin // 0x00: CRC_CTRL
                        if (s_axi_wstrb[0]) reg_ctrl[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_ctrl[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_ctrl[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_ctrl[31:24] <= s_axi_wdata[31:24];
                        if (s_axi_wdata[`CRC_CTRL_RESET_BIT]) begin
                            ctrl_soft_reset_o <= 1'b1;
                        end
                    end

                    4'h1: begin // 0x04: CRC_STATUS (W1C: Write 1 to Clear)
                        if (s_axi_wstrb[0]) begin
                            if (s_axi_wdata[`CRC_STATUS_DONE_BIT])  reg_status[`CRC_STATUS_DONE_BIT]  <= 1'b0;
                            if (s_axi_wdata[`CRC_STATUS_PASS_BIT])  reg_status[`CRC_STATUS_PASS_BIT]  <= 1'b0;
                            if (s_axi_wdata[`CRC_STATUS_ERROR_BIT]) reg_status[`CRC_STATUS_ERROR_BIT] <= 1'b0;
                        end
                    end

                    4'h3: begin // 0x0C: CRC_EXP_RESULT
                        if (s_axi_wstrb[0]) exp_crc_reg_o[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) exp_crc_reg_o[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) exp_crc_reg_o[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) exp_crc_reg_o[31:24] <= s_axi_wdata[31:24];
                        exp_crc_we_o <= 1'b1;
                    end

                    4'h4: begin // 0x10: CRC_POLY
                        if (s_axi_wstrb[0]) poly_rev_o[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) poly_rev_o[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) poly_rev_o[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) poly_rev_o[31:24] <= s_axi_wdata[31:24];
                    end

                    4'h5: begin // 0x14: CRC_INIT_VAL
                        if (s_axi_wstrb[0]) init_val_o[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) init_val_o[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) init_val_o[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) init_val_o[31:24] <= s_axi_wdata[31:24];
                    end

                    4'h7: begin // 0x1C: CRC_MANUAL_DATA (CPU direct write port)
                        manual_data_valid_o <= 1'b1;
                        manual_data_be_o    <= s_axi_wstrb;
                        manual_data_in_o    <= s_axi_wdata;
                        manual_data_last_o  <= reg_ctrl[7]; // optional bit for last
                    end

                    4'h8: begin // 0x20: CRC_ERROR_COUNT (Write 1 to clear)
                        clear_counters_o <= 1'b1;
                    end

                    4'h9: begin // 0x24: CRC_PASS_COUNT (Write 1 to clear)
                        clear_counters_o <= 1'b1;
                    end

                    4'hA: begin // 0x28: CRC_MODE_CONFIG
                        if (s_axi_wstrb[0]) reg_mode_config[7:0]   <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_mode_config[15:8]  <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) reg_mode_config[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_mode_config[31:24] <= s_axi_wdata[31:24];
                    end

                    default: ;
                endcase
            end

            // B channel response completion
            if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
                aw_en        <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // AXI4-Lite Read Channel Handshake & Register Reads
    // ------------------------------------------------------------------------
    reg [AXI_ADDR_WIDTH-1:0] raddr_latched;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
            raddr_latched <= 32'd0;
        end else begin
            // ARREADY generation
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                raddr_latched <= s_axi_araddr;
            end else begin
                s_axi_arready <= 1'b0;
            end

            // Read execution
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY

                case (s_axi_araddr[5:2])
                    4'h0: s_axi_rdata <= reg_ctrl;
                    4'h1: s_axi_rdata <= reg_status;
                    4'h2: s_axi_rdata <= calc_crc_result_i;
                    4'h3: s_axi_rdata <= exp_crc_reg_o;
                    4'h4: s_axi_rdata <= poly_rev_o;
                    4'h5: s_axi_rdata <= init_val_o;
                    4'h6: s_axi_rdata <= byte_count_i;
                    4'h7: s_axi_rdata <= 32'd0; // Write-only manual port
                    4'h8: s_axi_rdata <= error_count_i;
                    4'h9: s_axi_rdata <= pass_count_i;
                    4'hA: s_axi_rdata <= reg_mode_config;
                    default: s_axi_rdata <= 32'hDEADBEEF;
                endcase
            end else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule

`resetall
