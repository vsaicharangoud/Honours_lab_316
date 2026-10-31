`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ============================================================================
 * File: veer_cpu_subsystem.sv
 * Project: Reliable Data Transport System SoC
 * Description: Complete VeeR EL2 CPU Subsystem.
 *              Integrates:
 *                1. VeeR EL2 Core Complex (veer_wrapper)
 *                2. On-chip Tightly-Coupled Memories:
 *                   - DCCM (Data Closely Coupled Memory): 64 KB (4 x ram_4096x39)
 *                   - ICCM (Instruction Closely Coupled Memory): 64 KB (4 x ram_4096x39)
 *                   - ICache (Instruction Cache): 16 KB (4 x ram_512x71 data, 2 x ram_64x26 tag)
 *                3. LSU 64-bit to 32-bit AXI4 Bridge (veer_lsu_axi64_to_axi32_wrapper)
 *                4. IFU 64-bit to 32-bit AXI4 Bridge (veer_ifu_axi64_to_axi32_wrapper)
 *                5. Core PIC Interrupts mapping
 * ============================================================================
 */

module veer_cpu_subsystem
import el2_pkg::*;
#(
    `include "el2_param.vh"
)(
    input  wire                  clk,
    input  wire                  rst_n,      // Active-low asynchronous reset
    input  wire [31:1]           rst_vec,    // Boot reset vector (default: 32'h0000_0000)

    // ------------------------------------------------------------------------
    // External Interrupt Requests to VeeR PIC
    // ------------------------------------------------------------------------
    input  wire                  timer_irq,
    input  wire                  gpio_irq,
    input  wire                  fifo_irq,
    input  wire                  crc_irq,
    input  wire                  uart_irq,
    input  wire                  counter_irq,

    // ------------------------------------------------------------------------
    // IFU 32-bit AXI4 Master Interface (to Interconnect S00)
    // ------------------------------------------------------------------------
    output wire [7:0]            m_ifu_axi_arid,
    output wire [31:0]           m_ifu_axi_araddr,
    output wire [7:0]            m_ifu_axi_arlen,
    output wire [2:0]            m_ifu_axi_arsize,
    output wire [1:0]            m_ifu_axi_arburst,
    output wire                  m_ifu_axi_arlock,
    output wire [3:0]            m_ifu_axi_arcache,
    output wire [2:0]            m_ifu_axi_arprot,
    output wire [3:0]            m_ifu_axi_arqos,
    output wire [3:0]            m_ifu_axi_arregion,
    output wire                  m_ifu_axi_arvalid,
    input  wire                  m_ifu_axi_arready,

    input  wire [7:0]            m_ifu_axi_rid,
    input  wire [31:0]           m_ifu_axi_rdata,
    input  wire [1:0]            m_ifu_axi_rresp,
    input  wire                  m_ifu_axi_rlast,
    input  wire                  m_ifu_axi_rvalid,
    output wire                  m_ifu_axi_rready,

    // ------------------------------------------------------------------------
    // LSU 32-bit AXI4 Master Interface (to Interconnect S01)
    // ------------------------------------------------------------------------
    output wire [7:0]            m_lsu_axi_awid,
    output wire [31:0]           m_lsu_axi_awaddr,
    output wire [7:0]            m_lsu_axi_awlen,
    output wire [2:0]            m_lsu_axi_awsize,
    output wire [1:0]            m_lsu_axi_awburst,
    output wire                  m_lsu_axi_awlock,
    output wire [3:0]            m_lsu_axi_awcache,
    output wire [2:0]            m_lsu_axi_awprot,
    output wire [3:0]            m_lsu_axi_awqos,
    output wire [3:0]            m_lsu_axi_awregion,
    output wire                  m_lsu_axi_awvalid,
    input  wire                  m_lsu_axi_awready,

    output wire [31:0]           m_lsu_axi_wdata,
    output wire [3:0]            m_lsu_axi_wstrb,
    output wire                  m_lsu_axi_wlast,
    output wire                  m_lsu_axi_wvalid,
    input  wire                  m_lsu_axi_wready,

    input  wire [7:0]            m_lsu_axi_bid,
    input  wire [1:0]            m_lsu_axi_bresp,
    input  wire                  m_lsu_axi_bvalid,
    output wire                  m_lsu_axi_bready,

    output wire [7:0]            m_lsu_axi_arid,
    output wire [31:0]           m_lsu_axi_araddr,
    output wire [7:0]            m_lsu_axi_arlen,
    output wire [2:0]            m_lsu_axi_arsize,
    output wire [1:0]            m_lsu_axi_arburst,
    output wire                  m_lsu_axi_arlock,
    output wire [3:0]            m_lsu_axi_arcache,
    output wire [2:0]            m_lsu_axi_arprot,
    output wire [3:0]            m_lsu_axi_arqos,
    output wire [3:0]            m_lsu_axi_arregion,
    output wire                  m_lsu_axi_arvalid,
    input  wire                  m_lsu_axi_arready,

    input  wire [7:0]            m_lsu_axi_rid,
    input  wire [31:0]           m_lsu_axi_rdata,
    input  wire [1:0]            m_lsu_axi_rresp,
    input  wire                  m_lsu_axi_rlast,
    input  wire                  m_lsu_axi_rvalid,
    output wire                  m_lsu_axi_rready,

    // ------------------------------------------------------------------------
    // Trace and Monitoring
    // ------------------------------------------------------------------------
    output wire [31:0]           trace_rv_i_insn_ip,
    output wire [31:0]           trace_rv_i_address_ip,
    output wire                  trace_rv_i_valid_ip
);

    // ------------------------------------------------------------------------
    // Internal Wires for VeeR EL2 64-bit LSU
    // ------------------------------------------------------------------------
    wire                            lsu_axi_awvalid;
    wire                            lsu_axi_awready;
    wire [pt.LSU_BUS_TAG-1:0]       lsu_axi_awid;
    wire [31:0]                     lsu_axi_awaddr;
    wire [3:0]                      lsu_axi_awregion;
    wire [7:0]                      lsu_axi_awlen;
    wire [2:0]                      lsu_axi_awsize;
    wire [1:0]                      lsu_axi_awburst;
    wire                            lsu_axi_awlock;
    wire [3:0]                      lsu_axi_awcache;
    wire [2:0]                      lsu_axi_awprot;
    wire [3:0]                      lsu_axi_awqos;

    wire                            lsu_axi_wvalid;
    wire                            lsu_axi_wready;
    wire [63:0]                     lsu_axi_wdata;
    wire [7:0]                      lsu_axi_wstrb;
    wire                            lsu_axi_wlast;

    wire                            lsu_axi_bvalid;
    wire                            lsu_axi_bready;
    wire [1:0]                      lsu_axi_bresp;
    wire [pt.LSU_BUS_TAG-1:0]       lsu_axi_bid;

    wire                            lsu_axi_arvalid;
    wire                            lsu_axi_arready;
    wire [pt.LSU_BUS_TAG-1:0]       lsu_axi_arid;
    wire [31:0]                     lsu_axi_araddr;
    wire [3:0]                      lsu_axi_arregion;
    wire [7:0]                      lsu_axi_arlen;
    wire [2:0]                      lsu_axi_arsize;
    wire [1:0]                      lsu_axi_arburst;
    wire                            lsu_axi_arlock;
    wire [3:0]                      lsu_axi_arcache;
    wire [2:0]                      lsu_axi_arprot;
    wire [3:0]                      lsu_axi_arqos;

    wire                            lsu_axi_rvalid;
    wire                            lsu_axi_rready;
    wire [pt.LSU_BUS_TAG-1:0]       lsu_axi_rid;
    wire [63:0]                     lsu_axi_rdata;
    wire [1:0]                      lsu_axi_rresp;
    wire                            lsu_axi_rlast;

    // ------------------------------------------------------------------------
    // Internal Wires for VeeR EL2 64-bit IFU
    // ------------------------------------------------------------------------
    wire                            ifu_axi_arvalid;
    wire                            ifu_axi_arready;
    wire [pt.IFU_BUS_TAG-1:0]       ifu_axi_arid;
    wire [31:0]                     ifu_axi_araddr;
    wire [3:0]                      ifu_axi_arregion;
    wire [7:0]                      ifu_axi_arlen;
    wire [2:0]                      ifu_axi_arsize;
    wire [1:0]                      ifu_axi_arburst;
    wire                            ifu_axi_arlock;
    wire [3:0]                      ifu_axi_arcache;
    wire [2:0]                      ifu_axi_arprot;
    wire [3:0]                      ifu_axi_arqos;

    wire                            ifu_axi_rvalid;
    wire                            ifu_axi_rready;
    wire [pt.IFU_BUS_TAG-1:0]       ifu_axi_rid;
    wire [63:0]                     ifu_axi_rdata;
    wire [1:0]                      ifu_axi_rresp;
    wire                            ifu_axi_rlast;

    // ------------------------------------------------------------------------
    // Memory Interface Wires (ICCM, DCCM, ICACHE)
    // ------------------------------------------------------------------------
    wire mem_clk;
    // ICCM
    wire [pt.ICCM_NUM_BANKS-1:0] iccm_clken;
    wire [pt.ICCM_NUM_BANKS-1:0] iccm_wren_bank;
    wire [pt.ICCM_NUM_BANKS-1:0][pt.ICCM_BITS-1:pt.ICCM_BANK_INDEX_LO] iccm_addr_bank;
    wire [pt.ICCM_NUM_BANKS-1:0][31:0] iccm_bank_wr_data;
    wire [pt.ICCM_NUM_BANKS-1:0][pt.ICCM_ECC_WIDTH-1:0] iccm_bank_wr_ecc;
    wire [pt.ICCM_NUM_BANKS-1:0][31:0] iccm_bank_dout;
    wire [pt.ICCM_NUM_BANKS-1:0][pt.ICCM_ECC_WIDTH-1:0] iccm_bank_ecc;
    // DCCM
    wire [pt.DCCM_NUM_BANKS-1:0] dccm_clken;
    wire [pt.DCCM_NUM_BANKS-1:0] dccm_wren_bank;
    wire [pt.DCCM_NUM_BANKS-1:0][pt.DCCM_BITS-1:(pt.DCCM_BANK_BITS+2)] dccm_addr_bank;
    wire [pt.DCCM_NUM_BANKS-1:0][pt.DCCM_DATA_WIDTH-1:0] dccm_wr_data_bank;
    wire [pt.DCCM_NUM_BANKS-1:0][pt.DCCM_FDATA_WIDTH-pt.DCCM_DATA_WIDTH-1:0] dccm_wr_ecc_bank;
    wire [pt.DCCM_NUM_BANKS-1:0][pt.DCCM_DATA_WIDTH-1:0] dccm_bank_dout;
    wire [pt.DCCM_NUM_BANKS-1:0][pt.DCCM_FDATA_WIDTH-pt.DCCM_DATA_WIDTH-1:0] dccm_bank_ecc;
    // ICache
    wire [pt.ICACHE_BANKS_WAY-1:0][pt.ICACHE_NUM_WAYS-1:0] ic_b_sb_wren;
    wire [pt.ICACHE_BANKS_WAY-1:0][(71*pt.ICACHE_NUM_WAYS)-1:0] ic_b_sb_bit_en_vec;
    wire [pt.ICACHE_BANKS_WAY-1:0][70:0] ic_sb_wr_data;
    wire [pt.ICACHE_BANKS_WAY-1:0][pt.ICACHE_INDEX_HI:pt.ICACHE_DATA_INDEX_LO] ic_rw_addr_bank_q;
    wire [pt.ICACHE_BANKS_WAY-1:0] ic_bank_way_clken_final;
    wire [pt.ICACHE_NUM_WAYS-1:0][pt.ICACHE_BANKS_WAY-1:0] ic_bank_way_clken_final_up;
    wire [pt.ICACHE_BANKS_WAY-1:0][(71*pt.ICACHE_NUM_WAYS)-1:0] wb_packeddout_pre;
    wire [pt.ICACHE_NUM_WAYS-1:0][pt.ICACHE_BANKS_WAY-1:0][70:0] wb_dout_pre_up;
    wire [pt.ICACHE_NUM_WAYS-1:0] ic_tag_clken_final;
    wire [pt.ICACHE_NUM_WAYS-1:0] ic_tag_wren_q;
    wire [(26*pt.ICACHE_NUM_WAYS)-1:0] ic_tag_wren_biten_vec;
    wire [25:0] ic_tag_wr_data;
    wire [pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO] ic_rw_addr_q;
    wire [pt.ICACHE_NUM_WAYS-1:0][25:0] ic_tag_data_raw_pre;
    wire [(26*pt.ICACHE_NUM_WAYS)-1:0] ic_tag_data_raw_packed_pre;

    // Interrupt aggregation
    wire [pt.PIC_TOTAL_INT:1] extintsrc_req;
    assign extintsrc_req = {25'd0, counter_irq, uart_irq, crc_irq, fifo_irq, gpio_irq, timer_irq};

    // ------------------------------------------------------------------------
    // Instantiate VeeR EL2 Core Complex Wrapper
    // ------------------------------------------------------------------------
    veer_wrapper u_veer_core (
        .clk                    (clk),
        .rst_l                  (rst_n),
        .dbg_rst_l              (rst_n),
        .rst_vec                (rst_vec),
        .nmi_int                (1'b0),
        .nmi_vec                (31'd0),
        .jtag_id                (31'd0),

        .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip  (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(),
        .trace_rv_i_ecause_ip   (),
        .trace_rv_i_interrupt_ip(),
        .trace_rv_i_tval_ip     (),

        // LSU AXI signals
        .lsu_axi_awvalid        (lsu_axi_awvalid),
        .lsu_axi_awready        (lsu_axi_awready),
        .lsu_axi_awid           (lsu_axi_awid),
        .lsu_axi_awaddr         (lsu_axi_awaddr),
        .lsu_axi_awregion       (lsu_axi_awregion),
        .lsu_axi_awlen          (lsu_axi_awlen),
        .lsu_axi_awsize         (lsu_axi_awsize),
        .lsu_axi_awburst        (lsu_axi_awburst),
        .lsu_axi_awlock         (lsu_axi_awlock),
        .lsu_axi_awcache        (lsu_axi_awcache),
        .lsu_axi_awprot         (lsu_axi_awprot),
        .lsu_axi_awqos          (lsu_axi_awqos),
        .lsu_axi_wvalid         (lsu_axi_wvalid),
        .lsu_axi_wready         (lsu_axi_wready),
        .lsu_axi_wdata          (lsu_axi_wdata),
        .lsu_axi_wstrb          (lsu_axi_wstrb),
        .lsu_axi_wlast          (lsu_axi_wlast),
        .lsu_axi_bvalid         (lsu_axi_bvalid),
        .lsu_axi_bready         (lsu_axi_bready),
        .lsu_axi_bresp          (lsu_axi_bresp),
        .lsu_axi_bid            (lsu_axi_bid),
        .lsu_axi_arvalid        (lsu_axi_arvalid),
        .lsu_axi_arready        (lsu_axi_arready),
        .lsu_axi_arid           (lsu_axi_arid),
        .lsu_axi_araddr         (lsu_axi_araddr),
        .lsu_axi_arregion       (lsu_axi_arregion),
        .lsu_axi_arlen          (lsu_axi_arlen),
        .lsu_axi_arsize         (lsu_axi_arsize),
        .lsu_axi_arburst        (lsu_axi_arburst),
        .lsu_axi_arlock         (lsu_axi_arlock),
        .lsu_axi_arcache        (lsu_axi_arcache),
        .lsu_axi_arprot         (lsu_axi_arprot),
        .lsu_axi_arqos          (lsu_axi_arqos),
        .lsu_axi_rvalid         (lsu_axi_rvalid),
        .lsu_axi_rready         (lsu_axi_rready),
        .lsu_axi_rid            (lsu_axi_rid),
        .lsu_axi_rdata          (lsu_axi_rdata),
        .lsu_axi_rresp          (lsu_axi_rresp),
        .lsu_axi_rlast          (lsu_axi_rlast),

        // IFU AXI signals
        .ifu_axi_awvalid        (),
        .ifu_axi_awready        (1'b1),
        .ifu_axi_awid           (),
        .ifu_axi_awaddr         (),
        .ifu_axi_awregion       (),
        .ifu_axi_awlen          (),
        .ifu_axi_awsize         (),
        .ifu_axi_awburst        (),
        .ifu_axi_awlock         (),
        .ifu_axi_awcache        (),
        .ifu_axi_awprot         (),
        .ifu_axi_awqos          (),
        .ifu_axi_wvalid         (),
        .ifu_axi_wready         (1'b1),
        .ifu_axi_wdata          (),
        .ifu_axi_wstrb          (),
        .ifu_axi_wlast          (),
        .ifu_axi_bvalid         (1'b0),
        .ifu_axi_bready         (),
        .ifu_axi_bresp          (2'b00),
        .ifu_axi_bid            ({pt.IFU_BUS_TAG{1'b0}}),
        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_arid           (ifu_axi_arid),
        .ifu_axi_araddr         (ifu_axi_araddr),
        .ifu_axi_arregion       (ifu_axi_arregion),
        .ifu_axi_arlen          (ifu_axi_arlen),
        .ifu_axi_arsize         (ifu_axi_arsize),
        .ifu_axi_arburst        (ifu_axi_arburst),
        .ifu_axi_arlock         (ifu_axi_arlock),
        .ifu_axi_arcache        (ifu_axi_arcache),
        .ifu_axi_arprot         (ifu_axi_arprot),
        .ifu_axi_arqos          (ifu_axi_arqos),
        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready),
        .ifu_axi_rid            (ifu_axi_rid),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),

        // SB AXI (tied off)
        .sb_axi_awvalid         (),
        .sb_axi_awready         (1'b1),
        .sb_axi_awid            (),
        .sb_axi_awaddr          (),
        .sb_axi_awregion        (),
        .sb_axi_awlen           (),
        .sb_axi_awsize          (),
        .sb_axi_awburst         (),
        .sb_axi_awlock          (),
        .sb_axi_awcache         (),
        .sb_axi_awprot          (),
        .sb_axi_awqos           (),
        .sb_axi_wvalid          (),
        .sb_axi_wready          (1'b1),
        .sb_axi_wdata           (),
        .sb_axi_wstrb           (),
        .sb_axi_wlast           (),
        .sb_axi_bvalid          (1'b0),
        .sb_axi_bready          (),
        .sb_axi_bresp           (2'b00),
        .sb_axi_bid             ({pt.SB_BUS_TAG{1'b0}}),
        .sb_axi_arvalid         (),
        .sb_axi_arready         (1'b1),
        .sb_axi_arid            (),
        .sb_axi_araddr          (),
        .sb_axi_arregion        (),
        .sb_axi_arlen           (),
        .sb_axi_arsize          (),
        .sb_axi_arburst         (),
        .sb_axi_arlock          (),
        .sb_axi_arcache         (),
        .sb_axi_arprot          (),
        .sb_axi_arqos           (),
        .sb_axi_rvalid          (1'b0),
        .sb_axi_rready          (),
        .sb_axi_rid             ({pt.SB_BUS_TAG{1'b0}}),
        .sb_axi_rdata           (64'd0),
        .sb_axi_rresp           (2'b00),
        .sb_axi_rlast           (1'b0),

        // DMA AXI (tied off)
        .dma_axi_awvalid        (1'b0),
        .dma_axi_awready        (),
        .dma_axi_awid           ({pt.DMA_BUS_TAG{1'b0}}),
        .dma_axi_awaddr         (32'd0),
        .dma_axi_awsize         (3'd0),
        .dma_axi_awprot         (3'd0),
        .dma_axi_awlen          (8'd0),
        .dma_axi_awburst        (2'd0),
        .dma_axi_wvalid         (1'b0),
        .dma_axi_wready         (),
        .dma_axi_wdata          (64'd0),
        .dma_axi_wstrb          (8'd0),
        .dma_axi_wlast          (1'b0),
        .dma_axi_bvalid         (),
        .dma_axi_bready         (1'b1),
        .dma_axi_bresp          (),
        .dma_axi_bid            (),
        .dma_axi_arvalid        (1'b0),
        .dma_axi_arready        (),
        .dma_axi_arid           ({pt.DMA_BUS_TAG{1'b0}}),
        .dma_axi_araddr         (32'd0),
        .dma_axi_arsize         (3'd0),
        .dma_axi_arprot         (3'd0),
        .dma_axi_arlen          (8'd0),
        .dma_axi_arburst        (2'd0),
        .dma_axi_rvalid         (),
        .dma_axi_rready         (1'b1),
        .dma_axi_rid            (),
        .dma_axi_rdata          (),
        .dma_axi_rresp          (),
        .dma_axi_rlast          (),

        // Clocks & Interrupts
        .timer_int              (timer_irq),
        .soft_int               (1'b0),
        .extintsrc_req          (extintsrc_req),
        .lsu_bus_clk_en         (1'b1),
        .ifu_bus_clk_en         (1'b1),
        .dbg_bus_clk_en         (1'b1),
        .dma_bus_clk_en         (1'b1),

        // JTAG (tied off)
        .jtag_tck               (1'b0),
        .jtag_tms               (1'b0),
        .jtag_tdi               (1'b0),
        .jtag_trst_n            (1'b1),
        .jtag_tdo               (),
        .jtag_tdoEn             (),

        .core_id                (28'd0),
        .mpc_debug_halt_req     (1'b0),
        .mpc_debug_run_req      (1'b0),
        .mpc_reset_run_req      (1'b1),
        .mpc_debug_halt_ack     (),
        .mpc_debug_run_ack      (),
        .debug_brkpt_status     (),

        .i_cpu_halt_req         (1'b0),
        .o_cpu_halt_ack         (),
        .o_cpu_halt_status      (),
        .i_cpu_run_req          (1'b0),
        .o_debug_mode_status    (),
        .o_cpu_run_ack          (),
        .scan_mode              (1'b0),
        .mbist_mode             (1'b0),
        .dmi_core_enable        (1'b0),
        .dmi_uncore_enable      (1'b0),
        .dmi_uncore_en          (),
        .dmi_uncore_wr_en       (),
        .dmi_uncore_addr        (),
        .dmi_uncore_wdata       (),
        .dmi_uncore_rdata       (32'd0),
        .dmi_active             (),

        // Memory Export Ports
        .mem_clk                (mem_clk),
        .iccm_clken             (iccm_clken),
        .iccm_wren_bank         (iccm_wren_bank),
        .iccm_addr_bank         (iccm_addr_bank),
        .iccm_bank_wr_data      (iccm_bank_wr_data),
        .iccm_bank_wr_ecc       (iccm_bank_wr_ecc),
        .iccm_bank_dout         (iccm_bank_dout),
        .iccm_bank_ecc          (iccm_bank_ecc),

        .dccm_clken             (dccm_clken),
        .dccm_wren_bank         (dccm_wren_bank),
        .dccm_addr_bank         (dccm_addr_bank),
        .dccm_wr_data_bank      (dccm_wr_data_bank),
        .dccm_wr_ecc_bank       (dccm_wr_ecc_bank),
        .dccm_bank_dout         (dccm_bank_dout),
        .dccm_bank_ecc          (dccm_bank_ecc),

        .ic_b_sb_wren           (ic_b_sb_wren),
        .ic_b_sb_bit_en_vec     (ic_b_sb_bit_en_vec),
        .ic_sb_wr_data          (ic_sb_wr_data),
        .ic_rw_addr_bank_q      (ic_rw_addr_bank_q),
        .ic_bank_way_clken_final(ic_bank_way_clken_final),
        .ic_bank_way_clken_final_up(ic_bank_way_clken_final_up),
        .wb_packeddout_pre      (wb_packeddout_pre),
        .wb_dout_pre_up         (wb_dout_pre_up),
        .ic_tag_clken_final     (ic_tag_clken_final),
        .ic_tag_wren_q          (ic_tag_wren_q),
        .ic_tag_wren_biten_vec  (ic_tag_wren_biten_vec),
        .ic_tag_wr_data         (ic_tag_wr_data),
        .ic_rw_addr_q           (ic_rw_addr_q),
        .ic_tag_data_raw_pre    (ic_tag_data_raw_pre),
        .ic_tag_data_raw_packed_pre(ic_tag_data_raw_packed_pre),

        .iccm_ecc_single_error  (),
        .iccm_ecc_double_error  (),
        .dccm_ecc_single_error  (),
        .dccm_ecc_double_error  (),
        .dccm_write_readback_error()
    );

    // ------------------------------------------------------------------------
    // Tightly-Coupled Memories: DCCM (4 banks of ram_4096x39 = 64 KB)
    // ------------------------------------------------------------------------
    wire [38:0] dccm_wr_fdata_bank [pt.DCCM_NUM_BANKS-1:0];
    wire [38:0] dccm_bank_fdout    [pt.DCCM_NUM_BANKS-1:0];

    for (genvar i = 0; i < pt.DCCM_NUM_BANKS; i = i + 1) begin: gen_dccm_banks
        assign dccm_wr_fdata_bank[i] = {dccm_wr_ecc_bank[i], dccm_wr_data_bank[i]};
        assign dccm_bank_dout[i]     = dccm_bank_fdout[i][31:0];
        assign dccm_bank_ecc[i]      = dccm_bank_fdout[i][38:32];

        ram_4096x39 u_dccm_ram (
            .CLK      (mem_clk),
            .ME       (dccm_clken[i]),
            .WE       (dccm_wren_bank[i]),
            .ADR      (dccm_addr_bank[i]),
            .D        (dccm_wr_fdata_bank[i]),
            .Q        (dccm_bank_fdout[i]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );
    end

    // ------------------------------------------------------------------------
    // Tightly-Coupled Memories: ICCM (4 banks of ram_4096x39 = 64 KB)
    // ------------------------------------------------------------------------
    wire [38:0] iccm_bank_wr_fdata [pt.ICCM_NUM_BANKS-1:0];
    wire [38:0] iccm_bank_fdout    [pt.ICCM_NUM_BANKS-1:0];

    for (genvar j = 0; j < pt.ICCM_NUM_BANKS; j = j + 1) begin: gen_iccm_banks
        assign iccm_bank_wr_fdata[j] = {iccm_bank_wr_ecc[j], iccm_bank_wr_data[j]};
        assign iccm_bank_dout[j]     = iccm_bank_fdout[j][31:0];
        assign iccm_bank_ecc[j]      = iccm_bank_fdout[j][38:32];

        ram_4096x39 u_iccm_ram (
            .CLK      (mem_clk),
            .ME       (iccm_clken[j]),
            .WE       (iccm_wren_bank[j]),
            .ADR      (iccm_addr_bank[j]),
            .D        (iccm_bank_wr_fdata[j]),
            .Q        (iccm_bank_fdout[j]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );
    end

    // ------------------------------------------------------------------------
    // Instruction Cache RAMs (Data: ram_512x71, Tag: ram_64x26)
    // ------------------------------------------------------------------------
    assign wb_packeddout_pre = '0;
    for (genvar way = 0; way < pt.ICACHE_NUM_WAYS; way = way + 1) begin: gen_icache_ways
        // Tag RAM per way
        ram_64x26 u_itag_ram (
            .CLK      (mem_clk),
            .ME       (ic_tag_clken_final[way]),
            .WE       (ic_tag_wren_q[way]),
            .ADR      (ic_rw_addr_q[11:6]),
            .D        (ic_tag_wr_data),
            .Q        (ic_tag_data_raw_pre[way]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );

        // Data RAMs per sub-bank
        for (genvar bank = 0; bank < pt.ICACHE_BANKS_WAY; bank = bank + 1) begin: gen_icache_banks
            ram_512x71 u_idata_ram (
                .CLK      (mem_clk),
                .ME       (ic_bank_way_clken_final_up[way][bank]),
                .WE       (ic_b_sb_wren[bank][way]),
                .ADR      (ic_rw_addr_bank_q[bank]),
                .D        (ic_sb_wr_data[bank]),
                .Q        (wb_dout_pre_up[way][bank]),
                .ROP      (),
                .TEST1    (1'b0),
                .RME      (1'b0),
                .RM       (4'b0000),
                .LS       (1'b0),
                .DS       (1'b0),
                .SD       (1'b0),
                .TEST_RNM (1'b0),
                .BC1      (1'b0),
                .BC2      (1'b0)
            );
        end
    end

    // ------------------------------------------------------------------------
    // LSU 64-bit to 32-bit AXI4 Master Adapter
    // ------------------------------------------------------------------------
    assign m_lsu_axi_awregion = 4'd0;
    assign m_lsu_axi_arregion = 4'd0;

    veer_lsu_axi64_to_axi32_wrapper #(
        .LSU_BUS_TAG (pt.LSU_BUS_TAG),
        .M_ID_WIDTH  (8)
    ) u_lsu_adapter (
        .clk             (clk),
        .rst_n           (rst_n),

        // VeeR EL2 LSU Side (64-bit)
        .s_axi_awvalid   (lsu_axi_awvalid),
        .s_axi_awready   (lsu_axi_awready),
        .s_axi_awid      (lsu_axi_awid),
        .s_axi_awaddr    (lsu_axi_awaddr),
        .s_axi_awregion  (lsu_axi_awregion),
        .s_axi_awlen     (lsu_axi_awlen),
        .s_axi_awsize    (lsu_axi_awsize),
        .s_axi_awburst   (lsu_axi_awburst),
        .s_axi_awlock    (lsu_axi_awlock),
        .s_axi_awcache   (lsu_axi_awcache),
        .s_axi_awprot    (lsu_axi_awprot),
        .s_axi_awqos     (lsu_axi_awqos),

        .s_axi_wvalid    (lsu_axi_wvalid),
        .s_axi_wready    (lsu_axi_wready),
        .s_axi_wdata     (lsu_axi_wdata),
        .s_axi_wstrb     (lsu_axi_wstrb),
        .s_axi_wlast     (lsu_axi_wlast),

        .s_axi_bvalid    (lsu_axi_bvalid),
        .s_axi_bready    (lsu_axi_bready),
        .s_axi_bresp     (lsu_axi_bresp),
        .s_axi_bid       (lsu_axi_bid),

        .s_axi_arvalid   (lsu_axi_arvalid),
        .s_axi_arready   (lsu_axi_arready),
        .s_axi_arid      (lsu_axi_arid),
        .s_axi_araddr    (lsu_axi_araddr),
        .s_axi_arregion  (lsu_axi_arregion),
        .s_axi_arlen     (lsu_axi_arlen),
        .s_axi_arsize    (lsu_axi_arsize),
        .s_axi_arburst   (lsu_axi_arburst),
        .s_axi_arlock    (lsu_axi_arlock),
        .s_axi_arcache   (lsu_axi_arcache),
        .s_axi_arprot    (lsu_axi_arprot),
        .s_axi_arqos     (lsu_axi_arqos),

        .s_axi_rvalid    (lsu_axi_rvalid),
        .s_axi_rready    (lsu_axi_rready),
        .s_axi_rid       (lsu_axi_rid),
        .s_axi_rdata     (lsu_axi_rdata),
        .s_axi_rresp     (lsu_axi_rresp),
        .s_axi_rlast     (lsu_axi_rlast),

        // Interconnect Side (32-bit)
        .m_axi_awvalid   (m_lsu_axi_awvalid),
        .m_axi_awready   (m_lsu_axi_awready),
        .m_axi_awid      (m_lsu_axi_awid),
        .m_axi_awaddr    (m_lsu_axi_awaddr),
        .m_axi_awlen     (m_lsu_axi_awlen),
        .m_axi_awsize    (m_lsu_axi_awsize),
        .m_axi_awburst   (m_lsu_axi_awburst),
        .m_axi_awlock    (m_lsu_axi_awlock),
        .m_axi_awcache   (m_lsu_axi_awcache),
        .m_axi_awprot    (m_lsu_axi_awprot),
        .m_axi_awqos     (m_lsu_axi_awqos),
        .m_axi_awuser    (),

        .m_axi_wvalid    (m_lsu_axi_wvalid),
        .m_axi_wready    (m_lsu_axi_wready),
        .m_axi_wdata     (m_lsu_axi_wdata),
        .m_axi_wstrb     (m_lsu_axi_wstrb),
        .m_axi_wlast     (m_lsu_axi_wlast),
        .m_axi_wuser     (),

        .m_axi_bvalid    (m_lsu_axi_bvalid),
        .m_axi_bready    (m_lsu_axi_bready),
        .m_axi_bresp     (m_lsu_axi_bresp),
        .m_axi_bid       (m_lsu_axi_bid),
        .m_axi_buser     (1'b0),

        .m_axi_arvalid   (m_lsu_axi_arvalid),
        .m_axi_arready   (m_lsu_axi_arready),
        .m_axi_arid      (m_lsu_axi_arid),
        .m_axi_araddr    (m_lsu_axi_araddr),
        .m_axi_arlen     (m_lsu_axi_arlen),
        .m_axi_arsize    (m_lsu_axi_arsize),
        .m_axi_arburst   (m_lsu_axi_arburst),
        .m_axi_arlock    (m_lsu_axi_arlock),
        .m_axi_arcache   (m_lsu_axi_arcache),
        .m_axi_arprot    (m_lsu_axi_arprot),
        .m_axi_arqos     (m_lsu_axi_arqos),
        .m_axi_aruser    (),

        .m_axi_rvalid    (m_lsu_axi_rvalid),
        .m_axi_rready    (m_lsu_axi_rready),
        .m_axi_rid       (m_lsu_axi_rid),
        .m_axi_rdata     (m_lsu_axi_rdata),
        .m_axi_rresp     (m_lsu_axi_rresp),
        .m_axi_rlast     (m_lsu_axi_rlast),
        .m_axi_ruser     (1'b0)
    );

    // ------------------------------------------------------------------------
    // IFU 64-bit to 32-bit AXI4 Master Adapter
    // ------------------------------------------------------------------------
    veer_ifu_axi64_to_axi32_wrapper #(
        .S_ID_WIDTH (pt.IFU_BUS_TAG),
        .M_ID_WIDTH (8)
    ) u_ifu_adapter (
        .clk          (clk),
        .rst_n        (rst_n),

        // VeeR EL2 IFU Side (64-bit)
        .s_axi_arvalid(ifu_axi_arvalid),
        .s_axi_arready(ifu_axi_arready),
        .s_axi_arid   (ifu_axi_arid),
        .s_axi_araddr (ifu_axi_araddr),
        .s_axi_arregion(ifu_axi_arregion),
        .s_axi_arlen  (ifu_axi_arlen),
        .s_axi_arsize (ifu_axi_arsize),
        .s_axi_arburst(ifu_axi_arburst),
        .s_axi_arlock (ifu_axi_arlock),
        .s_axi_arcache(ifu_axi_arcache),
        .s_axi_arprot (ifu_axi_arprot),
        .s_axi_arqos  (ifu_axi_arqos),

        .s_axi_rvalid (ifu_axi_rvalid),
        .s_axi_rready (ifu_axi_rready),
        .s_axi_rid    (ifu_axi_rid),
        .s_axi_rdata  (ifu_axi_rdata),
        .s_axi_rresp  (ifu_axi_rresp),
        .s_axi_rlast  (ifu_axi_rlast),

        // Interconnect Side (32-bit)
        .m_axi_arvalid(m_ifu_axi_arvalid),
        .m_axi_arready(m_ifu_axi_arready),
        .m_axi_arid   (m_ifu_axi_arid),
        .m_axi_araddr (m_ifu_axi_araddr),
        .m_axi_arregion(m_ifu_axi_arregion),
        .m_axi_arlen  (m_ifu_axi_arlen),
        .m_axi_arsize (m_ifu_axi_arsize),
        .m_axi_arburst(m_ifu_axi_arburst),
        .m_axi_arlock (m_ifu_axi_arlock),
        .m_axi_arcache(m_ifu_axi_arcache),
        .m_axi_arprot (m_ifu_axi_arprot),
        .m_axi_arqos  (m_ifu_axi_arqos),

        .m_axi_rvalid (m_ifu_axi_rvalid),
        .m_axi_rready (m_ifu_axi_rready),
        .m_axi_rid    (m_ifu_axi_rid),
        .m_axi_rdata  (m_ifu_axi_rdata),
        .m_axi_rresp  (m_ifu_axi_rresp),
        .m_axi_rlast  (m_ifu_axi_rlast)
    );

endmodule
`resetall
