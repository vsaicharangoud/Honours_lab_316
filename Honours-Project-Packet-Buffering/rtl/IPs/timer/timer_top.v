/*
 * ============================================================================
 * File: timer_top.v
 * Project: Reliable Data Transport System SoC
 * Description: Top-Level AXI4 Timer IP Module.
 *              Directly interfaces to M03 of axi_interconnect_wrap_3x8
 *              Base address: 0x0002_1000  (Window: 0x0002_1000 - 0x0002_1FFF)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "timer_defines.vh"

module timer_top #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 8,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer USER_WIDTH = 1
)(
    // Clock and Reset
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset (from interconnect)
    input  wire                  rst_n,    // Active-low asynchronous/synchronous reset (optional)

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Address Channel (from Interconnect M03)
    // ------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [3:0]            s_axi_awcache,
    input  wire [2:0]            s_axi_awprot,
    input  wire [3:0]            s_axi_awqos,
    input  wire [3:0]            s_axi_awregion,
    input  wire [USER_WIDTH-1:0] s_axi_awuser,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Data Channel
    // ------------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire [USER_WIDTH-1:0] s_axi_wuser,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Response Channel
    // ------------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]            s_axi_bresp,
    output reg  [USER_WIDTH-1:0] s_axi_buser,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Read Address Channel
    // ------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [3:0]            s_axi_arcache,
    input  wire [2:0]            s_axi_arprot,
    input  wire [3:0]            s_axi_arqos,
    input  wire [3:0]            s_axi_arregion,
    input  wire [USER_WIDTH-1:0] s_axi_aruser,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Read Data Channel
    // ------------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]   s_axi_rid,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg  [USER_WIDTH-1:0] s_axi_ruser,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ------------------------------------------------------------------------
    // Hardware Peripheral Signals
    // ------------------------------------------------------------------------
    output wire                  timer_irq_o,
    output wire                  timer_match_o,
    output wire                  timer_pwm_o
);

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;

    // Combined synchronous reset: resets if rst is high or rst_n is low
    wire sys_rst = rst || (!rst_n);
    wire sys_rst_n = !sys_rst;

    // Control registers
    reg        reg_en;
    reg        reg_reload;
    reg        reg_ie;
    reg        reg_pwm_en;
    reg        reg_rst_pulse;
    reg [31:0] reg_compare;
    reg [15:0] reg_prescaler;
    reg [31:0] reg_load_val;
    reg        reg_load_we;
    reg        reg_clear_match;
    reg        reg_clear_ovf;

    // Core outputs
    wire [31:0] core_counter_val;
    wire        core_running;
    wire        core_match_flag;
    wire        core_ovf_flag;

    // Instantiate Timer Hardware Core
    timer_core u_timer_core (
        .clk            (clk),
        .rst_n          (sys_rst_n),
        .ctrl_en        (reg_en),
        .ctrl_reload    (reg_reload),
        .ctrl_rst       (reg_rst_pulse),
        .ctrl_ie        (reg_ie),
        .ctrl_pwm_en    (reg_pwm_en),
        .timer_load_val (reg_load_val),
        .timer_load_we  (reg_load_we),
        .compare_val    (reg_compare),
        .prescaler_div  (reg_prescaler),
        .clear_match    (reg_clear_match),
        .clear_ovf      (reg_clear_ovf),
        .counter_val_o  (core_counter_val),
        .running_o      (core_running),
        .match_flag_o   (core_match_flag),
        .ovf_flag_o     (core_ovf_flag),
        .match_pulse_o  (timer_match_o),
        .timer_irq_o    (timer_irq_o),
        .pwm_out_o      (timer_pwm_o)
    );

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write FSM & Independent Capture
    // ------------------------------------------------------------------------
    reg                  aw_captured;
    reg                  w_captured;
    reg [ID_WIDTH-1:0]   awid_hold;
    reg [ADDR_WIDTH-1:0] awaddr_hold;
    reg [7:0]            awlen_hold;
    reg [2:0]            awsize_hold;
    reg [1:0]            awburst_hold;
    reg [DATA_WIDTH-1:0] wdata_hold;
    reg [STRB_WIDTH-1:0] wstrb_hold;

    assign s_axi_awready = (!aw_captured) && (!s_axi_bvalid);
    assign s_axi_wready  = (!w_captured)  && (!s_axi_bvalid);

    wire write_fire = aw_captured && w_captured && (!s_axi_bvalid);
    wire [ADDR_WIDTH-1:0] eff_awaddr = aw_captured ? awaddr_hold : s_axi_awaddr;
    wire [DATA_WIDTH-1:0] eff_wdata  = w_captured  ? wdata_hold  : s_axi_wdata;
    wire [STRB_WIDTH-1:0] eff_wstrb  = w_captured  ? wstrb_hold  : s_axi_wstrb;
    wire [7:0] wr_offset = eff_awaddr[7:0];

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Read FSM
    // ------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] read_addr_hold;
    reg [ID_WIDTH-1:0]   read_id_hold;
    reg [7:0]            read_len_hold;
    reg [2:0]            read_size_hold;
    reg [1:0]            read_burst_hold;

    assign s_axi_arready = !s_axi_rvalid;
    wire [7:0] rd_offset = read_addr_hold[7:0];

    always @(posedge clk) begin
        if (sys_rst) begin
            reg_en          <= 1'b0;
            reg_reload      <= 1'b1; // Default periodic
            reg_ie          <= 1'b0;
            reg_pwm_en      <= 1'b0;
            reg_rst_pulse   <= 1'b0;
            reg_compare     <= 32'hFFFF_FFFF;
            reg_prescaler   <= 16'd0;
            reg_load_val    <= 32'd0;
            reg_load_we     <= 1'b0;
            reg_clear_match <= 1'b0;
            reg_clear_ovf   <= 1'b0;

            aw_captured     <= 1'b0;
            w_captured      <= 1'b0;
            awid_hold       <= {ID_WIDTH{1'b0}};
            awaddr_hold     <= {ADDR_WIDTH{1'b0}};
            awlen_hold      <= 8'd0;
            awsize_hold     <= 3'd0;
            awburst_hold    <= 2'd0;
            wdata_hold      <= {DATA_WIDTH{1'b0}};
            wstrb_hold      <= {STRB_WIDTH{1'b0}};

            s_axi_bid       <= {ID_WIDTH{1'b0}};
            s_axi_bresp     <= AXI_RESP_OKAY;
            s_axi_buser     <= {USER_WIDTH{1'b0}};
            s_axi_bvalid    <= 1'b0;

            read_addr_hold  <= {ADDR_WIDTH{1'b0}};
            read_id_hold    <= {ID_WIDTH{1'b0}};
            read_len_hold   <= 8'd0;
            read_size_hold  <= 3'd0;
            read_burst_hold <= 2'd0;

            s_axi_rid       <= {ID_WIDTH{1'b0}};
            s_axi_rdata     <= {DATA_WIDTH{1'b0}};
            s_axi_rresp     <= AXI_RESP_OKAY;
            s_axi_rlast     <= 1'b0;
            s_axi_ruser     <= {USER_WIDTH{1'b0}};
            s_axi_rvalid    <= 1'b0;
        end else begin
            // Self-clearing strobes
            reg_rst_pulse   <= 1'b0;
            reg_load_we     <= 1'b0;
            reg_clear_match <= 1'b0;
            reg_clear_ovf   <= 1'b0;

            // ----------------------------------------------------
            // Capture Write Channel
            // ----------------------------------------------------
            if (s_axi_awvalid && s_axi_awready) begin
                aw_captured  <= 1'b1;
                awid_hold    <= s_axi_awid;
                awaddr_hold  <= s_axi_awaddr;
                awlen_hold   <= s_axi_awlen;
                awsize_hold  <= s_axi_awsize;
                awburst_hold <= s_axi_awburst;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                w_captured <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (write_fire) begin
                aw_captured  <= 1'b0;
                w_captured   <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bid    <= awid_hold;
                s_axi_buser  <= {USER_WIDTH{1'b0}};

                if (awlen_hold != 8'd0 || eff_awaddr[1:0] != 2'b00) begin
                    s_axi_bresp <= AXI_RESP_SLVERR;
                end else begin
                    s_axi_bresp <= AXI_RESP_OKAY;
                    case (wr_offset)
                        `TIMER_REG_CTRL: begin
                            if (eff_wstrb[0]) begin
                                reg_en        <= eff_wdata[`TIMER_CTRL_EN_BIT];
                                reg_reload    <= eff_wdata[`TIMER_CTRL_RELOAD_BIT];
                                reg_rst_pulse <= eff_wdata[`TIMER_CTRL_RST_BIT];
                                reg_ie        <= eff_wdata[`TIMER_CTRL_IE_BIT];
                                reg_pwm_en    <= eff_wdata[`TIMER_CTRL_PWM_BIT];
                            end
                        end

                        `TIMER_REG_STATUS: begin
                            // W1C for status flags
                            if (eff_wstrb[0]) begin
                                if (eff_wdata[`TIMER_STAT_MATCH_BIT])
                                    reg_clear_match <= 1'b1;
                                if (eff_wdata[`TIMER_STAT_OVF_BIT])
                                    reg_clear_ovf <= 1'b1;
                            end
                        end

                        `TIMER_REG_VALUE: begin
                            reg_load_we <= 1'b1;
                            if (eff_wstrb[0]) reg_load_val[7:0]   <= eff_wdata[7:0];
                            if (eff_wstrb[1]) reg_load_val[15:8]  <= eff_wdata[15:8];
                            if (eff_wstrb[2]) reg_load_val[23:16] <= eff_wdata[23:16];
                            if (eff_wstrb[3]) reg_load_val[31:24] <= eff_wdata[31:24];
                        end

                        `TIMER_REG_COMPARE: begin
                            if (eff_wstrb[0]) reg_compare[7:0]   <= eff_wdata[7:0];
                            if (eff_wstrb[1]) reg_compare[15:8]  <= eff_wdata[15:8];
                            if (eff_wstrb[2]) reg_compare[23:16] <= eff_wdata[23:16];
                            if (eff_wstrb[3]) reg_compare[31:24] <= eff_wdata[31:24];
                        end

                        `TIMER_REG_PRESCALER: begin
                            if (eff_wstrb[0]) reg_prescaler[7:0]  <= eff_wdata[7:0];
                            if (eff_wstrb[1]) reg_prescaler[15:8] <= eff_wdata[15:8];
                        end

                        default: begin
                            s_axi_bresp <= AXI_RESP_SLVERR;
                        end
                    endcase
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // ----------------------------------------------------
            // Capture Read Channel
            // ----------------------------------------------------
            if (s_axi_arvalid && s_axi_arready) begin
                read_addr_hold  <= s_axi_araddr;
                read_id_hold    <= s_axi_arid;
                read_len_hold   <= s_axi_arlen;
                read_size_hold  <= s_axi_arsize;
                read_burst_hold <= s_axi_arburst;

                s_axi_rvalid <= 1'b1;
                s_axi_rlast  <= 1'b1;
                s_axi_rid    <= s_axi_arid;
                s_axi_ruser  <= {USER_WIDTH{1'b0}};

                if (s_axi_arlen != 8'd0 || s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rresp <= AXI_RESP_SLVERR;
                    s_axi_rdata <= 32'd0;
                end else begin
                    s_axi_rresp <= AXI_RESP_OKAY;
                    case (s_axi_araddr[7:0])
                        `TIMER_REG_CTRL: begin
                            s_axi_rdata <= {27'd0, reg_pwm_en, reg_ie, 1'b0, reg_reload, reg_en};
                        end

                        `TIMER_REG_STATUS: begin
                            s_axi_rdata <= {29'd0, core_ovf_flag, core_match_flag, core_running};
                        end

                        `TIMER_REG_VALUE: begin
                            s_axi_rdata <= core_counter_val;
                        end

                        `TIMER_REG_COMPARE: begin
                            s_axi_rdata <= reg_compare;
                        end

                        `TIMER_REG_PRESCALER: begin
                            s_axi_rdata <= {16'd0, reg_prescaler};
                        end

                        default: begin
                            s_axi_rresp <= AXI_RESP_SLVERR;
                            s_axi_rdata <= 32'd0;
                        end
                    endcase
                end
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                s_axi_rlast  <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
