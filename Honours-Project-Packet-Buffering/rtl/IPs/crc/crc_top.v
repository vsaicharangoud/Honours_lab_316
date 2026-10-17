/*
 * ============================================================================
 * File: crc_top.v
 * Project: Reliable Data Transport System SoC
 * Description: Top-Level CRC-32 IP Core Module.
 *              Integrates:
 *                1. AXI4-Lite Slave Register Interface (Base: 0x000A_0000)
 *                2. Streaming Packet Datapath Interface (Path A: From FIFO)
 *                3. Hardware CRC-32 Integrity Verification Engine
 *                4. Event flags (PASS / ERROR / DONE) & Interrupt output
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "crc_defines.vh"

module crc_top #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32
)(
    // Global Clock and Reset
    input  wire                          clk,
    input  wire                          rst_n,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (CPU Configuration & Status)
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
    // Streaming Packet Interface (Path A: Incoming from Packet FIFO)
    // ------------------------------------------------------------------------
    input  wire [31:0]                   s_axis_tdata,
    input  wire [3:0]                    s_axis_tkeep,
    input  wire                          s_axis_tlast,
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,

    // ------------------------------------------------------------------------
    // Dedicated Hardware Signals to SoC (Packet Counter / CPU / System)
    // ------------------------------------------------------------------------
    output wire                          crc_pass_o,   // Pulse: Packet CRC verified PASS
    output wire                          crc_error_o,  // Pulse: Packet CRC MISMATCH
    output wire                          crc_done_o,   // Pulse: Packet verification complete
    output wire                          crc_busy_o,   // Level: Packet check active
    output wire                          irq_o         // Level: Interrupt request to PIC
);

    // ------------------------------------------------------------------------
    // Interconnect Wires between AXI4-Lite Slave and CRC Checker
    // ------------------------------------------------------------------------
    wire        ctrl_enable;
    wire        ctrl_soft_reset;
    wire        ctrl_auto_clear;
    wire [1:0]  mode_config;
    wire [31:0] poly_rev;
    wire [31:0] init_val;
    wire [31:0] exp_crc_reg;
    wire        exp_crc_we;
    wire        clear_counters;

    wire        manual_data_valid;
    wire [3:0]  manual_data_be;
    wire [31:0] manual_data_in;
    wire        manual_data_last;

    wire        checker_busy;
    wire        checker_done;
    wire        checker_pass;
    wire        checker_error;
    wire [31:0] calc_crc_result;
    wire [31:0] exp_crc_result;
    wire [31:0] byte_count;
    wire [31:0] pass_count;
    wire [31:0] error_count;

    // Direct output assignments
    assign crc_busy_o = checker_busy;

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Instance
    // ------------------------------------------------------------------------
    crc_axi4lite_slave #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) u_axi4lite_slave (
        .aclk                (clk),
        .aresetn             (rst_n),

        // AXI Write Address Channel
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awprot        (s_axi_awprot),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),

        // AXI Write Data Channel
        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),

        // AXI Write Response Channel
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),

        // AXI Read Address Channel
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arprot        (s_axi_arprot),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),

        // AXI Read Data Channel
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),

        // Internal Control Outputs to Checker
        .ctrl_enable_o       (ctrl_enable),
        .ctrl_soft_reset_o   (ctrl_soft_reset),
        .ctrl_auto_clear_o   (ctrl_auto_clear),
        .mode_config_o       (mode_config),
        .poly_rev_o          (poly_rev),
        .init_val_o          (init_val),
        .exp_crc_reg_o       (exp_crc_reg),
        .exp_crc_we_o        (exp_crc_we),
        .clear_counters_o    (clear_counters),

        // Manual Data Port
        .manual_data_valid_o (manual_data_valid),
        .manual_data_be_o    (manual_data_be),
        .manual_data_in_o    (manual_data_in),
        .manual_data_last_o  (manual_data_last),

        // Internal Status Inputs from Checker (Edge Pulses)
        .checker_busy_i      (checker_busy),
        .checker_done_i      (crc_done_o),
        .checker_pass_i      (crc_pass_o),
        .checker_error_i     (crc_error_o),
        .calc_crc_result_i   (calc_crc_result),
        .exp_crc_result_i    (exp_crc_result),
        .byte_count_i        (byte_count),
        .pass_count_i        (pass_count),
        .error_count_i       (error_count),

        // Interrupt Output
        .irq_o               (irq_o)
    );

    // ------------------------------------------------------------------------
    // CRC Checker Datapath Instance
    // ------------------------------------------------------------------------
    crc_checker u_crc_checker (
        .clk                 (clk),
        .rst_n               (rst_n),

        // Control & Configuration
        .enable              (ctrl_enable),
        .soft_reset          (ctrl_soft_reset),
        .mode_config         (mode_config),
        .auto_clear          (ctrl_auto_clear),
        .poly_rev            (poly_rev),
        .init_val            (init_val),
        .exp_crc_reg         (exp_crc_reg),
        .exp_crc_we          (exp_crc_we),
        .clear_counters      (clear_counters),

        // Manual Data Port
        .manual_data_valid   (manual_data_valid),
        .manual_data_be      (manual_data_be),
        .manual_data_in      (manual_data_in),
        .manual_data_last    (manual_data_last),

        // Streaming Packet Interface (From Packet FIFO)
        .s_axis_tdata        (s_axis_tdata),
        .s_axis_tkeep        (s_axis_tkeep),
        .s_axis_tlast        (s_axis_tlast),
        .s_axis_tvalid       (s_axis_tvalid),
        .s_axis_tready       (s_axis_tready),

        // Hardware Event Flags
        .crc_pass_o          (crc_pass_o),
        .crc_error_o         (crc_error_o),
        .crc_done_o          (crc_done_o),
        .crc_busy_o          (checker_busy),

        // Status & Result Registers to AXI-Lite
        .calc_crc_result_o   (calc_crc_result),
        .exp_crc_result_o    (exp_crc_result),
        .byte_count_o        (byte_count),
        .pass_count_o        (pass_count),
        .error_count_o       (error_count),
        .status_busy_o       (),
        .status_done_o       (),
        .status_pass_o       (),
        .status_error_o      ()
    );

endmodule

`resetall
