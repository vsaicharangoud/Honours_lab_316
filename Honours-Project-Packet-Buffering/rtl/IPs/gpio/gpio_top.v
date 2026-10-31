/*
 * ============================================================================
 * File: gpio_top.v
 * Project: Reliable Data Transport System SoC
 * Description: Top-Level AXI4 GPIO IP Module.
 *              Directly interfaces to M04 of axi_interconnect_wrap_3x8
 *              Base address: 0x0002_2000  (Window: 0x0002_2000 - 0x0002_2FFF)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "gpio_defines.vh"

module gpio_top #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 8,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer USER_WIDTH = 1,
    parameter integer GPIO_WIDTH = 32
)(
    // Clock and Reset
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset (from interconnect)
    input  wire                  rst_n,    // Active-low reset (optional)

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Address Channel (from Interconnect M04)
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
    // Dedicated Physical GPIO Pins & Interrupt to SoC
    // ------------------------------------------------------------------------
    input  wire [GPIO_WIDTH-1:0] gpio_i,
    output wire [GPIO_WIDTH-1:0] gpio_o,
    output wire [GPIO_WIDTH-1:0] gpio_oe,
    output wire                  gpio_irq_o
);

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;

    wire sys_rst = rst || (!rst_n);
    wire sys_rst_n = !sys_rst;

    // Registers and control wires
    reg  [GPIO_WIDTH-1:0] reg_data_out;
    reg                   data_out_we;
    reg  [GPIO_WIDTH-1:0] reg_dir;
    reg                   dir_we;
    reg  [GPIO_WIDTH-1:0] reg_set;
    reg  [GPIO_WIDTH-1:0] reg_clear;
    reg  [GPIO_WIDTH-1:0] reg_int_en;
    reg                   int_en_we;
    reg  [GPIO_WIDTH-1:0] reg_int_type;
    reg                   int_type_we;
    reg  [GPIO_WIDTH-1:0] reg_int_pol;
    reg                   int_pol_we;
    reg  [GPIO_WIDTH-1:0] reg_int_stat_clear;

    // Core outputs
    wire [GPIO_WIDTH-1:0] core_data_in;
    wire [GPIO_WIDTH-1:0] core_data_out;
    wire [GPIO_WIDTH-1:0] core_dir;
    wire [GPIO_WIDTH-1:0] core_int_en;
    wire [GPIO_WIDTH-1:0] core_int_type;
    wire [GPIO_WIDTH-1:0] core_int_pol;
    wire [GPIO_WIDTH-1:0] core_int_stat;

    gpio_core #(
        .GPIO_WIDTH (GPIO_WIDTH)
    ) u_gpio_core (
        .clk            (clk),
        .rst_n          (sys_rst_n),
        .data_out_write (reg_data_out),
        .data_out_we    (data_out_we),
        .dir_write      (reg_dir),
        .dir_we         (dir_we),
        .set_pulse      (reg_set),
        .clear_pulse    (reg_clear),
        .int_en_write   (reg_int_en),
        .int_en_we      (int_en_we),
        .int_type_write (reg_int_type),
        .int_type_we    (int_type_we),
        .int_pol_write  (reg_int_pol),
        .int_pol_we     (int_pol_we),
        .int_stat_clear (reg_int_stat_clear),
        .data_in_o      (core_data_in),
        .data_out_o     (core_data_out),
        .dir_o          (core_dir),
        .int_en_o       (core_int_en),
        .int_type_o     (core_int_type),
        .int_pol_o      (core_int_pol),
        .int_stat_o     (core_int_stat),
        .gpio_i         (gpio_i),
        .gpio_o         (gpio_o),
        .gpio_oe        (gpio_oe),
        .gpio_irq_o     (gpio_irq_o)
    );

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Channel Handling
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
    // AXI4 Subordinate Read Channel Handling
    // ------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] read_addr_hold;
    reg [ID_WIDTH-1:0]   read_id_hold;
    reg [7:0]            read_len_hold;
    reg [2:0]            read_size_hold;
    reg [1:0]            read_burst_hold;

    assign s_axi_arready = !s_axi_rvalid;
    wire [7:0] rd_offset = read_addr_hold[7:0];

    // Helper function for byte strobe merge
    function [31:0] apply_strb(input [31:0] orig_val, input [31:0] new_val, input [3:0] strb);
        apply_strb = {
            strb[3] ? new_val[31:24] : orig_val[31:24],
            strb[2] ? new_val[23:16] : orig_val[23:16],
            strb[1] ? new_val[15:8]  : orig_val[15:8],
            strb[0] ? new_val[7:0]   : orig_val[7:0]
        };
    endfunction

    always @(posedge clk) begin
        if (sys_rst) begin
            reg_data_out        <= {GPIO_WIDTH{1'b0}};
            data_out_we         <= 1'b0;
            reg_dir             <= {GPIO_WIDTH{1'b0}};
            dir_we              <= 1'b0;
            reg_set             <= {GPIO_WIDTH{1'b0}};
            reg_clear           <= {GPIO_WIDTH{1'b0}};
            reg_int_en          <= {GPIO_WIDTH{1'b0}};
            int_en_we           <= 1'b0;
            reg_int_type        <= {GPIO_WIDTH{1'b0}};
            int_type_we         <= 1'b0;
            reg_int_pol         <= {GPIO_WIDTH{1'b0}};
            int_pol_we          <= 1'b0;
            reg_int_stat_clear  <= {GPIO_WIDTH{1'b0}};

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
            // Self-clearing write strobes
            data_out_we        <= 1'b0;
            dir_we             <= 1'b0;
            reg_set            <= {GPIO_WIDTH{1'b0}};
            reg_clear          <= {GPIO_WIDTH{1'b0}};
            int_en_we          <= 1'b0;
            int_type_we        <= 1'b0;
            int_pol_we         <= 1'b0;
            reg_int_stat_clear <= {GPIO_WIDTH{1'b0}};

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
                        `GPIO_REG_DATA_OUT: begin
                            data_out_we  <= 1'b1;
                            reg_data_out <= apply_strb(core_data_out, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_DIR: begin
                            dir_we  <= 1'b1;
                            reg_dir <= apply_strb(core_dir, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_SET: begin
                            reg_set <= apply_strb(32'd0, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_CLEAR: begin
                            reg_clear <= apply_strb(32'd0, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_INT_EN: begin
                            int_en_we  <= 1'b1;
                            reg_int_en <= apply_strb(core_int_en, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_INT_TYPE: begin
                            int_type_we  <= 1'b1;
                            reg_int_type <= apply_strb(core_int_type, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_INT_POL: begin
                            int_pol_we  <= 1'b1;
                            reg_int_pol <= apply_strb(core_int_pol, eff_wdata, eff_wstrb);
                        end

                        `GPIO_REG_INT_STATUS: begin
                            // W1C for pending interrupt bits
                            reg_int_stat_clear <= apply_strb(32'd0, eff_wdata, eff_wstrb);
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
                        `GPIO_REG_DATA_IN:    s_axi_rdata <= core_data_in;
                        `GPIO_REG_DATA_OUT:   s_axi_rdata <= core_data_out;
                        `GPIO_REG_DIR:        s_axi_rdata <= core_dir;
                        `GPIO_REG_INT_EN:     s_axi_rdata <= core_int_en;
                        `GPIO_REG_INT_TYPE:   s_axi_rdata <= core_int_type;
                        `GPIO_REG_INT_POL:    s_axi_rdata <= core_int_pol;
                        `GPIO_REG_INT_STATUS: s_axi_rdata <= core_int_stat;
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
