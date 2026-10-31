/*
 * ============================================================================
 * File: timer_axi4lite.v
 * Project: Reliable Data Transport System SoC
 * Description: AXI4-Lite Subordinate Interface for Timer IP
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "timer_defines.vh"

module timer_axi4lite #(
    parameter integer ADDR_WIDTH = 32
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    // AXI4-Lite Write Address Channel
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]            s_axi_awprot,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [31:0]           s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]            s_axi_arprot,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [31:0]           s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    // Hardware Signals
    output wire                  timer_irq_o,
    output wire                  timer_match_o,
    output wire                  timer_pwm_o
);

    wire [7:0] dummy_id = 8'd0;

    timer_top #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (8),
        .STRB_WIDTH (4),
        .USER_WIDTH (1)
    ) u_timer_axi (
        .clk             (aclk),
        .rst             (!aresetn),
        .rst_n           (aresetn),

        .s_axi_awid      (dummy_id),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (8'd0),
        .s_axi_awsize    (3'd2),
        .s_axi_awburst   (2'd0),
        .s_axi_awlock    (1'b0),
        .s_axi_awcache   (4'd0),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awqos     (4'd0),
        .s_axi_awregion  (4'd0),
        .s_axi_awuser    (1'b0),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),

        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (1'b1),
        .s_axi_wuser     (1'b0),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),

        .s_axi_bid       (),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_buser     (),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),

        .s_axi_arid      (dummy_id),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (8'd0),
        .s_axi_arsize    (3'd2),
        .s_axi_arburst   (2'd0),
        .s_axi_arlock    (1'b0),
        .s_axi_arcache   (4'd0),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arqos     (4'd0),
        .s_axi_arregion  (4'd0),
        .s_axi_aruser    (1'b0),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),

        .s_axi_rid       (),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rlast     (),
        .s_axi_ruser     (),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),

        .timer_irq_o     (timer_irq_o),
        .timer_match_o   (timer_match_o),
        .timer_pwm_o     (timer_pwm_o)
    );

endmodule

`default_nettype wire
