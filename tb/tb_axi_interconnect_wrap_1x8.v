/*
 * Testbench: tb_axi_interconnect_wrap_1x8.v
 *
 * Transactions:
 *   Write 1 : addr=0x0000_0010  data=0xDEAD_BEEF  -> slave M00
 *   Write 2 : addr=0x0001_0020  data=0xCAFE_BABE  -> slave M01
 *   Write 3 : addr=0x0002_0030  data=0xA5A5_A5A5  -> slave M02
 *   Read  1 : addr=0x0002_1040               -> slave M03  (returns 0x1234_5678)
 *   Read  2 : addr=0x0002_2050               -> slave M04  (returns 0xABCD_EF01)
 *
 * All transactions are single-beat (AWLEN/ARLEN = 0).
 *
 * Waveform dump : FSDB via $fsdbDumpfile / $fsdbDumpvars  (Verdi)
 *                 VPD  via $vcdplusfile / $vcdplusdumpon   (VCS+DVE)
 *
 * Compile & run (VCS example):
 *   vcs -full64 -sverilog -debug_all \
 *       +define+DUMP_FSDB \
 *       rtl/axi_interconnect_wrap_1x8.v \
 *       rtl/axi_interconnect.v \
 *       rtl/arbiter.v \
 *       rtl/priority_encoder.v \
 *       tb/tb_axi_interconnect_wrap_1x8.v \
 *       -o simv
 *   ./simv
 */

`timescale 1ns / 1ps
`default_nettype none

// ============================================================
//  Reusable dummy AXI4 slave
//  - Immediately accepts AW & W, returns BRESP = OKAY
//  - Immediately accepts AR, returns fixed RDATA = READ_DATA
// ============================================================
module axi_slave_dummy #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter STRB_WIDTH  = DATA_WIDTH/8,
    parameter ID_WIDTH    = 8,
    parameter USER_WIDTH  = 1,
    parameter READ_DATA   = 32'hDEAD_DEAD  // default read-back value
)(
    input  wire                  clk,
    input  wire                  rst,

    /* Write address channel */
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
    output reg                   s_axi_awready,

    /* Write data channel */
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire [USER_WIDTH-1:0] s_axi_wuser,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    /* Write response channel */
    output reg  [ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]            s_axi_bresp,
    output reg  [USER_WIDTH-1:0] s_axi_buser,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    /* Read address channel */
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
    output reg                   s_axi_arready,

    /* Read data channel */
    output reg  [ID_WIDTH-1:0]   s_axi_rid,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg  [USER_WIDTH-1:0] s_axi_ruser,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready
);

    // ---- Write logic ------------------------------------------------
    // Accept write address immediately
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_awready <= 1'b0;
        end else begin
            // one-cycle pulse ready
            s_axi_awready <= s_axi_awvalid & ~s_axi_awready;
        end
    end

    // Accept write data immediately
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_wready <= 1'b0;
        end else begin
            s_axi_wready <= s_axi_wvalid & ~s_axi_wready;
        end
    end

    // Capture AW ID for BRESP
    reg [ID_WIDTH-1:0] aw_id_r;
    reg                aw_accepted;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            aw_id_r     <= {ID_WIDTH{1'b0}};
            aw_accepted <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_id_r     <= s_axi_awid;
                aw_accepted <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                aw_accepted <= 1'b0;
            end
        end
    end

    // Wait for both AW and W acceptance before issuing BRESP
    reg w_accepted;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_accepted <= 1'b0;
        end else begin
            if (s_axi_wvalid && s_axi_wready && s_axi_wlast)
                w_accepted <= 1'b1;
            else if (s_axi_bvalid && s_axi_bready)
                w_accepted <= 1'b0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_bid    <= {ID_WIDTH{1'b0}};
            s_axi_buser  <= {USER_WIDTH{1'b0}};
        end else begin
            if (!s_axi_bvalid && aw_accepted && w_accepted) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
                s_axi_bid    <= aw_id_r;
                s_axi_buser  <= {USER_WIDTH{1'b0}};
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---- Read logic -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_arready <= 1'b0;
        end else begin
            s_axi_arready <= s_axi_arvalid & ~s_axi_arready;
        end
    end

    reg [ID_WIDTH-1:0] ar_id_r;
    reg                ar_accepted;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ar_id_r     <= {ID_WIDTH{1'b0}};
            ar_accepted <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                ar_id_r     <= s_axi_arid;
                ar_accepted <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready && s_axi_rlast) begin
                ar_accepted <= 1'b0;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= {DATA_WIDTH{1'b0}};
            s_axi_rresp  <= 2'b00;
            s_axi_rlast  <= 1'b0;
            s_axi_rid    <= {ID_WIDTH{1'b0}};
            s_axi_ruser  <= {USER_WIDTH{1'b0}};
        end else begin
            if (!s_axi_rvalid && ar_accepted) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= READ_DATA;
                s_axi_rresp  <= 2'b00; // OKAY
                s_axi_rlast  <= 1'b1;  // single-beat
                s_axi_rid    <= ar_id_r;
                s_axi_ruser  <= {USER_WIDTH{1'b0}};
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                s_axi_rlast  <= 1'b0;
            end
        end
    end

endmodule


// ============================================================
//  Testbench top
// ============================================================
module tb_axi_interconnect_wrap_1x8;

    // ----------------------------------------------------------
    // Parameters (must match DUT defaults)
    // ----------------------------------------------------------
    parameter DATA_WIDTH  = 32;
    parameter ADDR_WIDTH  = 32;
    parameter STRB_WIDTH  = DATA_WIDTH / 8;
    parameter ID_WIDTH    = 8;
    parameter USER_WIDTH  = 1;

    // Slave address map — 8 x 4KB naturally-aligned non-overlapping windows
    // Rule: BASE & (2^ADDR_WIDTH - 1) == 0  AND  no overlaps
    // addr_width=12 => window=4KB=0x1000, bases at 0x0000, 0x1000, 0x2000...
    parameter M00_BASE = 32'h0000_0000;   // 0x0000_0000 – 0x0000_0FFF
    parameter M01_BASE = 32'h0000_1000;   // 0x0000_1000 – 0x0000_1FFF
    parameter M02_BASE = 32'h0000_2000;   // 0x0000_2000 – 0x0000_2FFF
    parameter M03_BASE = 32'h0000_3000;   // 0x0000_3000 – 0x0000_3FFF
    parameter M04_BASE = 32'h0000_4000;   // 0x0000_4000 – 0x0000_4FFF
    parameter M05_BASE = 32'h0000_5000;   // 0x0000_5000 – 0x0000_5FFF
    parameter M06_BASE = 32'h0000_6000;   // 0x0000_6000 – 0x0000_6FFF
    parameter M07_BASE = 32'h0000_7000;   // 0x0000_7000 – 0x0000_7FFF

    // ----------------------------------------------------------
    // Clock & reset
    // ----------------------------------------------------------
    reg clk;
    reg rst;

    initial clk = 1'b0;
    always #5 clk = ~clk;  // 100 MHz

    // ----------------------------------------------------------
    // AXI master (testbench) -> DUT slave port
    // ----------------------------------------------------------
    // Write address
    reg  [ID_WIDTH-1:0]   s00_awid;
    reg  [ADDR_WIDTH-1:0] s00_awaddr;
    reg  [7:0]            s00_awlen;
    reg  [2:0]            s00_awsize;
    reg  [1:0]            s00_awburst;
    reg                   s00_awlock;
    reg  [3:0]            s00_awcache;
    reg  [2:0]            s00_awprot;
    reg  [3:0]            s00_awqos;
    reg  [USER_WIDTH-1:0] s00_awuser;
    reg                   s00_awvalid;
    wire                  s00_awready;

    // Write data
    reg  [DATA_WIDTH-1:0] s00_wdata;
    reg  [STRB_WIDTH-1:0] s00_wstrb;
    reg                   s00_wlast;
    reg  [USER_WIDTH-1:0] s00_wuser;
    reg                   s00_wvalid;
    wire                  s00_wready;

    // Write response
    wire [ID_WIDTH-1:0]   s00_bid;
    wire [1:0]            s00_bresp;
    wire [USER_WIDTH-1:0] s00_buser;
    wire                  s00_bvalid;
    reg                   s00_bready;

    // Read address
    reg  [ID_WIDTH-1:0]   s00_arid;
    reg  [ADDR_WIDTH-1:0] s00_araddr;
    reg  [7:0]            s00_arlen;
    reg  [2:0]            s00_arsize;
    reg  [1:0]            s00_arburst;
    reg                   s00_arlock;
    reg  [3:0]            s00_arcache;
    reg  [2:0]            s00_arprot;
    reg  [3:0]            s00_arqos;
    reg  [USER_WIDTH-1:0] s00_aruser;
    reg                   s00_arvalid;
    wire                  s00_arready;

    // Read data
    wire [ID_WIDTH-1:0]   s00_rid;
    wire [DATA_WIDTH-1:0] s00_rdata;
    wire [1:0]            s00_rresp;
    wire                  s00_rlast;
    wire [USER_WIDTH-1:0] s00_ruser;
    wire                  s00_rvalid;
    reg                   s00_rready;

    // ----------------------------------------------------------
    // DUT -> Slave port wires (m00..m07)
    // ----------------------------------------------------------
    // Macro to declare one master port wire bundle
`define DECL_M_WIRES(N) \
    wire [ID_WIDTH-1:0]   m``N``_awid; \
    wire [ADDR_WIDTH-1:0] m``N``_awaddr; \
    wire [7:0]            m``N``_awlen; \
    wire [2:0]            m``N``_awsize; \
    wire [1:0]            m``N``_awburst; \
    wire                  m``N``_awlock; \
    wire [3:0]            m``N``_awcache; \
    wire [2:0]            m``N``_awprot; \
    wire [3:0]            m``N``_awqos; \
    wire [3:0]            m``N``_awregion; \
    wire [USER_WIDTH-1:0] m``N``_awuser; \
    wire                  m``N``_awvalid; \
    wire                  m``N``_awready; \
    wire [DATA_WIDTH-1:0] m``N``_wdata; \
    wire [STRB_WIDTH-1:0] m``N``_wstrb; \
    wire                  m``N``_wlast; \
    wire [USER_WIDTH-1:0] m``N``_wuser; \
    wire                  m``N``_wvalid; \
    wire                  m``N``_wready; \
    wire [ID_WIDTH-1:0]   m``N``_bid; \
    wire [1:0]            m``N``_bresp; \
    wire [USER_WIDTH-1:0] m``N``_buser; \
    wire                  m``N``_bvalid; \
    wire                  m``N``_bready; \
    wire [ID_WIDTH-1:0]   m``N``_arid; \
    wire [ADDR_WIDTH-1:0] m``N``_araddr; \
    wire [7:0]            m``N``_arlen; \
    wire [2:0]            m``N``_arsize; \
    wire [1:0]            m``N``_arburst; \
    wire                  m``N``_arlock; \
    wire [3:0]            m``N``_arcache; \
    wire [2:0]            m``N``_arprot; \
    wire [3:0]            m``N``_arqos; \
    wire [3:0]            m``N``_arregion; \
    wire [USER_WIDTH-1:0] m``N``_aruser; \
    wire                  m``N``_arvalid; \
    wire                  m``N``_arready; \
    wire [ID_WIDTH-1:0]   m``N``_rid; \
    wire [DATA_WIDTH-1:0] m``N``_rdata; \
    wire [1:0]            m``N``_rresp; \
    wire                  m``N``_rlast; \
    wire [USER_WIDTH-1:0] m``N``_ruser; \
    wire                  m``N``_rvalid; \
    wire                  m``N``_rready;

    `DECL_M_WIRES(00)
    `DECL_M_WIRES(01)
    `DECL_M_WIRES(02)
    `DECL_M_WIRES(03)
    `DECL_M_WIRES(04)
    `DECL_M_WIRES(05)
    `DECL_M_WIRES(06)
    `DECL_M_WIRES(07)

    // ----------------------------------------------------------
    // DUT instantiation
    //
    // All slaves: ADDR_WIDTH=12 (4KB window), bases at 4KB increments.
    // BASE_ADDR & (2^12 - 1) == 0  ✓  for all.
    // No overlapping ranges ✓
    // ----------------------------------------------------------
    axi_interconnect_wrap_1x8 #(
        .DATA_WIDTH       (DATA_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .STRB_WIDTH       (STRB_WIDTH),
        .ID_WIDTH         (ID_WIDTH),
        .M00_BASE_ADDR    (M00_BASE),  .M00_ADDR_WIDTH  (32'd12),
        .M01_BASE_ADDR    (M01_BASE),  .M01_ADDR_WIDTH  (32'd12),
        .M02_BASE_ADDR    (M02_BASE),  .M02_ADDR_WIDTH  (32'd12),
        .M03_BASE_ADDR    (M03_BASE),  .M03_ADDR_WIDTH  (32'd12),
        .M04_BASE_ADDR    (M04_BASE),  .M04_ADDR_WIDTH  (32'd12),
        .M05_BASE_ADDR    (M05_BASE),  .M05_ADDR_WIDTH  (32'd12),
        .M06_BASE_ADDR    (M06_BASE),  .M06_ADDR_WIDTH  (32'd12),
        .M07_BASE_ADDR    (M07_BASE),  .M07_ADDR_WIDTH  (32'd12)
    ) dut (
        .clk             (clk),
        .rst             (rst),

        // Slave (from TB master)
        .s00_axi_awid    (s00_awid),
        .s00_axi_awaddr  (s00_awaddr),
        .s00_axi_awlen   (s00_awlen),
        .s00_axi_awsize  (s00_awsize),
        .s00_axi_awburst (s00_awburst),
        .s00_axi_awlock  (s00_awlock),
        .s00_axi_awcache (s00_awcache),
        .s00_axi_awprot  (s00_awprot),
        .s00_axi_awqos   (s00_awqos),
        .s00_axi_awuser  (s00_awuser),
        .s00_axi_awvalid (s00_awvalid),
        .s00_axi_awready (s00_awready),
        .s00_axi_wdata   (s00_wdata),
        .s00_axi_wstrb   (s00_wstrb),
        .s00_axi_wlast   (s00_wlast),
        .s00_axi_wuser   (s00_wuser),
        .s00_axi_wvalid  (s00_wvalid),
        .s00_axi_wready  (s00_wready),
        .s00_axi_bid     (s00_bid),
        .s00_axi_bresp   (s00_bresp),
        .s00_axi_buser   (s00_buser),
        .s00_axi_bvalid  (s00_bvalid),
        .s00_axi_bready  (s00_bready),
        .s00_axi_arid    (s00_arid),
        .s00_axi_araddr  (s00_araddr),
        .s00_axi_arlen   (s00_arlen),
        .s00_axi_arsize  (s00_arsize),
        .s00_axi_arburst (s00_arburst),
        .s00_axi_arlock  (s00_arlock),
        .s00_axi_arcache (s00_arcache),
        .s00_axi_arprot  (s00_arprot),
        .s00_axi_arqos   (s00_arqos),
        .s00_axi_aruser  (s00_aruser),
        .s00_axi_arvalid (s00_arvalid),
        .s00_axi_arready (s00_arready),
        .s00_axi_rid     (s00_rid),
        .s00_axi_rdata   (s00_rdata),
        .s00_axi_rresp   (s00_rresp),
        .s00_axi_rlast   (s00_rlast),
        .s00_axi_ruser   (s00_ruser),
        .s00_axi_rvalid  (s00_rvalid),
        .s00_axi_rready  (s00_rready),

        // Master ports -> dummy slaves
        .m00_axi_awid    (m00_awid),    .m00_axi_awaddr  (m00_awaddr),
        .m00_axi_awlen   (m00_awlen),   .m00_axi_awsize  (m00_awsize),
        .m00_axi_awburst (m00_awburst), .m00_axi_awlock  (m00_awlock),
        .m00_axi_awcache (m00_awcache), .m00_axi_awprot  (m00_awprot),
        .m00_axi_awqos   (m00_awqos),   .m00_axi_awregion(m00_awregion),
        .m00_axi_awuser  (m00_awuser),  .m00_axi_awvalid (m00_awvalid),
        .m00_axi_awready (m00_awready), .m00_axi_wdata   (m00_wdata),
        .m00_axi_wstrb   (m00_wstrb),   .m00_axi_wlast   (m00_wlast),
        .m00_axi_wuser   (m00_wuser),   .m00_axi_wvalid  (m00_wvalid),
        .m00_axi_wready  (m00_wready),  .m00_axi_bid     (m00_bid),
        .m00_axi_bresp   (m00_bresp),   .m00_axi_buser   (m00_buser),
        .m00_axi_bvalid  (m00_bvalid),  .m00_axi_bready  (m00_bready),
        .m00_axi_arid    (m00_arid),    .m00_axi_araddr  (m00_araddr),
        .m00_axi_arlen   (m00_arlen),   .m00_axi_arsize  (m00_arsize),
        .m00_axi_arburst (m00_arburst), .m00_axi_arlock  (m00_arlock),
        .m00_axi_arcache (m00_arcache), .m00_axi_arprot  (m00_arprot),
        .m00_axi_arqos   (m00_arqos),   .m00_axi_arregion(m00_arregion),
        .m00_axi_aruser  (m00_aruser),  .m00_axi_arvalid (m00_arvalid),
        .m00_axi_arready (m00_arready), .m00_axi_rid     (m00_rid),
        .m00_axi_rdata   (m00_rdata),   .m00_axi_rresp   (m00_rresp),
        .m00_axi_rlast   (m00_rlast),   .m00_axi_ruser   (m00_ruser),
        .m00_axi_rvalid  (m00_rvalid),  .m00_axi_rready  (m00_rready),

        .m01_axi_awid    (m01_awid),    .m01_axi_awaddr  (m01_awaddr),
        .m01_axi_awlen   (m01_awlen),   .m01_axi_awsize  (m01_awsize),
        .m01_axi_awburst (m01_awburst), .m01_axi_awlock  (m01_awlock),
        .m01_axi_awcache (m01_awcache), .m01_axi_awprot  (m01_awprot),
        .m01_axi_awqos   (m01_awqos),   .m01_axi_awregion(m01_awregion),
        .m01_axi_awuser  (m01_awuser),  .m01_axi_awvalid (m01_awvalid),
        .m01_axi_awready (m01_awready), .m01_axi_wdata   (m01_wdata),
        .m01_axi_wstrb   (m01_wstrb),   .m01_axi_wlast   (m01_wlast),
        .m01_axi_wuser   (m01_wuser),   .m01_axi_wvalid  (m01_wvalid),
        .m01_axi_wready  (m01_wready),  .m01_axi_bid     (m01_bid),
        .m01_axi_bresp   (m01_bresp),   .m01_axi_buser   (m01_buser),
        .m01_axi_bvalid  (m01_bvalid),  .m01_axi_bready  (m01_bready),
        .m01_axi_arid    (m01_arid),    .m01_axi_araddr  (m01_araddr),
        .m01_axi_arlen   (m01_arlen),   .m01_axi_arsize  (m01_arsize),
        .m01_axi_arburst (m01_arburst), .m01_axi_arlock  (m01_arlock),
        .m01_axi_arcache (m01_arcache), .m01_axi_arprot  (m01_arprot),
        .m01_axi_arqos   (m01_arqos),   .m01_axi_arregion(m01_arregion),
        .m01_axi_aruser  (m01_aruser),  .m01_axi_arvalid (m01_arvalid),
        .m01_axi_arready (m01_arready), .m01_axi_rid     (m01_rid),
        .m01_axi_rdata   (m01_rdata),   .m01_axi_rresp   (m01_rresp),
        .m01_axi_rlast   (m01_rlast),   .m01_axi_ruser   (m01_ruser),
        .m01_axi_rvalid  (m01_rvalid),  .m01_axi_rready  (m01_rready),

        .m02_axi_awid    (m02_awid),    .m02_axi_awaddr  (m02_awaddr),
        .m02_axi_awlen   (m02_awlen),   .m02_axi_awsize  (m02_awsize),
        .m02_axi_awburst (m02_awburst), .m02_axi_awlock  (m02_awlock),
        .m02_axi_awcache (m02_awcache), .m02_axi_awprot  (m02_awprot),
        .m02_axi_awqos   (m02_awqos),   .m02_axi_awregion(m02_awregion),
        .m02_axi_awuser  (m02_awuser),  .m02_axi_awvalid (m02_awvalid),
        .m02_axi_awready (m02_awready), .m02_axi_wdata   (m02_wdata),
        .m02_axi_wstrb   (m02_wstrb),   .m02_axi_wlast   (m02_wlast),
        .m02_axi_wuser   (m02_wuser),   .m02_axi_wvalid  (m02_wvalid),
        .m02_axi_wready  (m02_wready),  .m02_axi_bid     (m02_bid),
        .m02_axi_bresp   (m02_bresp),   .m02_axi_buser   (m02_buser),
        .m02_axi_bvalid  (m02_bvalid),  .m02_axi_bready  (m02_bready),
        .m02_axi_arid    (m02_arid),    .m02_axi_araddr  (m02_araddr),
        .m02_axi_arlen   (m02_arlen),   .m02_axi_arsize  (m02_arsize),
        .m02_axi_arburst (m02_arburst), .m02_axi_arlock  (m02_arlock),
        .m02_axi_arcache (m02_arcache), .m02_axi_arprot  (m02_arprot),
        .m02_axi_arqos   (m02_arqos),   .m02_axi_arregion(m02_arregion),
        .m02_axi_aruser  (m02_aruser),  .m02_axi_arvalid (m02_arvalid),
        .m02_axi_arready (m02_arready), .m02_axi_rid     (m02_rid),
        .m02_axi_rdata   (m02_rdata),   .m02_axi_rresp   (m02_rresp),
        .m02_axi_rlast   (m02_rlast),   .m02_axi_ruser   (m02_ruser),
        .m02_axi_rvalid  (m02_rvalid),  .m02_axi_rready  (m02_rready),

        .m03_axi_awid    (m03_awid),    .m03_axi_awaddr  (m03_awaddr),
        .m03_axi_awlen   (m03_awlen),   .m03_axi_awsize  (m03_awsize),
        .m03_axi_awburst (m03_awburst), .m03_axi_awlock  (m03_awlock),
        .m03_axi_awcache (m03_awcache), .m03_axi_awprot  (m03_awprot),
        .m03_axi_awqos   (m03_awqos),   .m03_axi_awregion(m03_awregion),
        .m03_axi_awuser  (m03_awuser),  .m03_axi_awvalid (m03_awvalid),
        .m03_axi_awready (m03_awready), .m03_axi_wdata   (m03_wdata),
        .m03_axi_wstrb   (m03_wstrb),   .m03_axi_wlast   (m03_wlast),
        .m03_axi_wuser   (m03_wuser),   .m03_axi_wvalid  (m03_wvalid),
        .m03_axi_wready  (m03_wready),  .m03_axi_bid     (m03_bid),
        .m03_axi_bresp   (m03_bresp),   .m03_axi_buser   (m03_buser),
        .m03_axi_bvalid  (m03_bvalid),  .m03_axi_bready  (m03_bready),
        .m03_axi_arid    (m03_arid),    .m03_axi_araddr  (m03_araddr),
        .m03_axi_arlen   (m03_arlen),   .m03_axi_arsize  (m03_arsize),
        .m03_axi_arburst (m03_arburst), .m03_axi_arlock  (m03_arlock),
        .m03_axi_arcache (m03_arcache), .m03_axi_arprot  (m03_arprot),
        .m03_axi_arqos   (m03_arqos),   .m03_axi_arregion(m03_arregion),
        .m03_axi_aruser  (m03_aruser),  .m03_axi_arvalid (m03_arvalid),
        .m03_axi_arready (m03_arready), .m03_axi_rid     (m03_rid),
        .m03_axi_rdata   (m03_rdata),   .m03_axi_rresp   (m03_rresp),
        .m03_axi_rlast   (m03_rlast),   .m03_axi_ruser   (m03_ruser),
        .m03_axi_rvalid  (m03_rvalid),  .m03_axi_rready  (m03_rready),

        .m04_axi_awid    (m04_awid),    .m04_axi_awaddr  (m04_awaddr),
        .m04_axi_awlen   (m04_awlen),   .m04_axi_awsize  (m04_awsize),
        .m04_axi_awburst (m04_awburst), .m04_axi_awlock  (m04_awlock),
        .m04_axi_awcache (m04_awcache), .m04_axi_awprot  (m04_awprot),
        .m04_axi_awqos   (m04_awqos),   .m04_axi_awregion(m04_awregion),
        .m04_axi_awuser  (m04_awuser),  .m04_axi_awvalid (m04_awvalid),
        .m04_axi_awready (m04_awready), .m04_axi_wdata   (m04_wdata),
        .m04_axi_wstrb   (m04_wstrb),   .m04_axi_wlast   (m04_wlast),
        .m04_axi_wuser   (m04_wuser),   .m04_axi_wvalid  (m04_wvalid),
        .m04_axi_wready  (m04_wready),  .m04_axi_bid     (m04_bid),
        .m04_axi_bresp   (m04_bresp),   .m04_axi_buser   (m04_buser),
        .m04_axi_bvalid  (m04_bvalid),  .m04_axi_bready  (m04_bready),
        .m04_axi_arid    (m04_arid),    .m04_axi_araddr  (m04_araddr),
        .m04_axi_arlen   (m04_arlen),   .m04_axi_arsize  (m04_arsize),
        .m04_axi_arburst (m04_arburst), .m04_axi_arlock  (m04_arlock),
        .m04_axi_arcache (m04_arcache), .m04_axi_arprot  (m04_arprot),
        .m04_axi_arqos   (m04_arqos),   .m04_axi_arregion(m04_arregion),
        .m04_axi_aruser  (m04_aruser),  .m04_axi_arvalid (m04_arvalid),
        .m04_axi_arready (m04_arready), .m04_axi_rid     (m04_rid),
        .m04_axi_rdata   (m04_rdata),   .m04_axi_rresp   (m04_rresp),
        .m04_axi_rlast   (m04_rlast),   .m04_axi_ruser   (m04_ruser),
        .m04_axi_rvalid  (m04_rvalid),  .m04_axi_rready  (m04_rready),

        .m05_axi_awid    (m05_awid),    .m05_axi_awaddr  (m05_awaddr),
        .m05_axi_awlen   (m05_awlen),   .m05_axi_awsize  (m05_awsize),
        .m05_axi_awburst (m05_awburst), .m05_axi_awlock  (m05_awlock),
        .m05_axi_awcache (m05_awcache), .m05_axi_awprot  (m05_awprot),
        .m05_axi_awqos   (m05_awqos),   .m05_axi_awregion(m05_awregion),
        .m05_axi_awuser  (m05_awuser),  .m05_axi_awvalid (m05_awvalid),
        .m05_axi_awready (m05_awready), .m05_axi_wdata   (m05_wdata),
        .m05_axi_wstrb   (m05_wstrb),   .m05_axi_wlast   (m05_wlast),
        .m05_axi_wuser   (m05_wuser),   .m05_axi_wvalid  (m05_wvalid),
        .m05_axi_wready  (m05_wready),  .m05_axi_bid     (m05_bid),
        .m05_axi_bresp   (m05_bresp),   .m05_axi_buser   (m05_buser),
        .m05_axi_bvalid  (m05_bvalid),  .m05_axi_bready  (m05_bready),
        .m05_axi_arid    (m05_arid),    .m05_axi_araddr  (m05_araddr),
        .m05_axi_arlen   (m05_arlen),   .m05_axi_arsize  (m05_arsize),
        .m05_axi_arburst (m05_arburst), .m05_axi_arlock  (m05_arlock),
        .m05_axi_arcache (m05_arcache), .m05_axi_arprot  (m05_arprot),
        .m05_axi_arqos   (m05_arqos),   .m05_axi_arregion(m05_arregion),
        .m05_axi_aruser  (m05_aruser),  .m05_axi_arvalid (m05_arvalid),
        .m05_axi_arready (m05_arready), .m05_axi_rid     (m05_rid),
        .m05_axi_rdata   (m05_rdata),   .m05_axi_rresp   (m05_rresp),
        .m05_axi_rlast   (m05_rlast),   .m05_axi_ruser   (m05_ruser),
        .m05_axi_rvalid  (m05_rvalid),  .m05_axi_rready  (m05_rready),

        .m06_axi_awid    (m06_awid),    .m06_axi_awaddr  (m06_awaddr),
        .m06_axi_awlen   (m06_awlen),   .m06_axi_awsize  (m06_awsize),
        .m06_axi_awburst (m06_awburst), .m06_axi_awlock  (m06_awlock),
        .m06_axi_awcache (m06_awcache), .m06_axi_awprot  (m06_awprot),
        .m06_axi_awqos   (m06_awqos),   .m06_axi_awregion(m06_awregion),
        .m06_axi_awuser  (m06_awuser),  .m06_axi_awvalid (m06_awvalid),
        .m06_axi_awready (m06_awready), .m06_axi_wdata   (m06_wdata),
        .m06_axi_wstrb   (m06_wstrb),   .m06_axi_wlast   (m06_wlast),
        .m06_axi_wuser   (m06_wuser),   .m06_axi_wvalid  (m06_wvalid),
        .m06_axi_wready  (m06_wready),  .m06_axi_bid     (m06_bid),
        .m06_axi_bresp   (m06_bresp),   .m06_axi_buser   (m06_buser),
        .m06_axi_bvalid  (m06_bvalid),  .m06_axi_bready  (m06_bready),
        .m06_axi_arid    (m06_arid),    .m06_axi_araddr  (m06_araddr),
        .m06_axi_arlen   (m06_arlen),   .m06_axi_arsize  (m06_arsize),
        .m06_axi_arburst (m06_arburst), .m06_axi_arlock  (m06_arlock),
        .m06_axi_arcache (m06_arcache), .m06_axi_arprot  (m06_arprot),
        .m06_axi_arqos   (m06_arqos),   .m06_axi_arregion(m06_arregion),
        .m06_axi_aruser  (m06_aruser),  .m06_axi_arvalid (m06_arvalid),
        .m06_axi_arready (m06_arready), .m06_axi_rid     (m06_rid),
        .m06_axi_rdata   (m06_rdata),   .m06_axi_rresp   (m06_rresp),
        .m06_axi_rlast   (m06_rlast),   .m06_axi_ruser   (m06_ruser),
        .m06_axi_rvalid  (m06_rvalid),  .m06_axi_rready  (m06_rready),

        .m07_axi_awid    (m07_awid),    .m07_axi_awaddr  (m07_awaddr),
        .m07_axi_awlen   (m07_awlen),   .m07_axi_awsize  (m07_awsize),
        .m07_axi_awburst (m07_awburst), .m07_axi_awlock  (m07_awlock),
        .m07_axi_awcache (m07_awcache), .m07_axi_awprot  (m07_awprot),
        .m07_axi_awqos   (m07_awqos),   .m07_axi_awregion(m07_awregion),
        .m07_axi_awuser  (m07_awuser),  .m07_axi_awvalid (m07_awvalid),
        .m07_axi_awready (m07_awready), .m07_axi_wdata   (m07_wdata),
        .m07_axi_wstrb   (m07_wstrb),   .m07_axi_wlast   (m07_wlast),
        .m07_axi_wuser   (m07_wuser),   .m07_axi_wvalid  (m07_wvalid),
        .m07_axi_wready  (m07_wready),  .m07_axi_bid     (m07_bid),
        .m07_axi_bresp   (m07_bresp),   .m07_axi_buser   (m07_buser),
        .m07_axi_bvalid  (m07_bvalid),  .m07_axi_bready  (m07_bready),
        .m07_axi_arid    (m07_arid),    .m07_axi_araddr  (m07_araddr),
        .m07_axi_arlen   (m07_arlen),   .m07_axi_arsize  (m07_arsize),
        .m07_axi_arburst (m07_arburst), .m07_axi_arlock  (m07_arlock),
        .m07_axi_arcache (m07_arcache), .m07_axi_arprot  (m07_arprot),
        .m07_axi_arqos   (m07_arqos),   .m07_axi_arregion(m07_arregion),
        .m07_axi_aruser  (m07_aruser),  .m07_axi_arvalid (m07_arvalid),
        .m07_axi_arready (m07_arready), .m07_axi_rid     (m07_rid),
        .m07_axi_rdata   (m07_rdata),   .m07_axi_rresp   (m07_rresp),
        .m07_axi_rlast   (m07_rlast),   .m07_axi_ruser   (m07_ruser),
        .m07_axi_rvalid  (m07_rvalid),  .m07_axi_rready  (m07_rready)
    );

    // ----------------------------------------------------------
    // Dummy slave instances
    // ----------------------------------------------------------
    // Macro to instantiate one slave
`define INST_SLAVE(N, RDAT) \
    axi_slave_dummy #( \
        .DATA_WIDTH (DATA_WIDTH), \
        .ADDR_WIDTH (ADDR_WIDTH), \
        .STRB_WIDTH (STRB_WIDTH), \
        .ID_WIDTH   (ID_WIDTH), \
        .USER_WIDTH (USER_WIDTH), \
        .READ_DATA  (RDAT) \
    ) slave_m``N ( \
        .clk           (clk), \
        .rst           (rst), \
        .s_axi_awid    (m``N``_awid), \
        .s_axi_awaddr  (m``N``_awaddr), \
        .s_axi_awlen   (m``N``_awlen), \
        .s_axi_awsize  (m``N``_awsize), \
        .s_axi_awburst (m``N``_awburst), \
        .s_axi_awlock  (m``N``_awlock), \
        .s_axi_awcache (m``N``_awcache), \
        .s_axi_awprot  (m``N``_awprot), \
        .s_axi_awqos   (m``N``_awqos), \
        .s_axi_awregion(m``N``_awregion), \
        .s_axi_awuser  (m``N``_awuser), \
        .s_axi_awvalid (m``N``_awvalid), \
        .s_axi_awready (m``N``_awready), \
        .s_axi_wdata   (m``N``_wdata), \
        .s_axi_wstrb   (m``N``_wstrb), \
        .s_axi_wlast   (m``N``_wlast), \
        .s_axi_wuser   (m``N``_wuser), \
        .s_axi_wvalid  (m``N``_wvalid), \
        .s_axi_wready  (m``N``_wready), \
        .s_axi_bid     (m``N``_bid), \
        .s_axi_bresp   (m``N``_bresp), \
        .s_axi_buser   (m``N``_buser), \
        .s_axi_bvalid  (m``N``_bvalid), \
        .s_axi_bready  (m``N``_bready), \
        .s_axi_arid    (m``N``_arid), \
        .s_axi_araddr  (m``N``_araddr), \
        .s_axi_arlen   (m``N``_arlen), \
        .s_axi_arsize  (m``N``_arsize), \
        .s_axi_arburst (m``N``_arburst), \
        .s_axi_arlock  (m``N``_arlock), \
        .s_axi_arcache (m``N``_arcache), \
        .s_axi_arprot  (m``N``_arprot), \
        .s_axi_arqos   (m``N``_arqos), \
        .s_axi_arregion(m``N``_arregion), \
        .s_axi_aruser  (m``N``_aruser), \
        .s_axi_arvalid (m``N``_arvalid), \
        .s_axi_arready (m``N``_arready), \
        .s_axi_rid     (m``N``_rid), \
        .s_axi_rdata   (m``N``_rdata), \
        .s_axi_rresp   (m``N``_rresp), \
        .s_axi_rlast   (m``N``_rlast), \
        .s_axi_ruser   (m``N``_ruser), \
        .s_axi_rvalid  (m``N``_rvalid), \
        .s_axi_rready  (m``N``_rready) \
    );

    `INST_SLAVE(00, 32'hBEEF_0000)
    `INST_SLAVE(01, 32'hBEEF_0001)
    `INST_SLAVE(02, 32'hBEEF_0002)
    `INST_SLAVE(03, 32'h1234_5678)   // Read 1 returns this
    `INST_SLAVE(04, 32'hABCD_EF01)   // Read 2 returns this
    `INST_SLAVE(05, 32'hBEEF_0005)
    `INST_SLAVE(06, 32'hBEEF_0006)
    `INST_SLAVE(07, 32'hBEEF_0007)

    // ----------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------
    integer cycle_cnt;
    initial cycle_cnt = 0;
    always @(posedge clk) begin
        cycle_cnt = cycle_cnt + 1;
        if (cycle_cnt > 10000) begin
            $display("[TIMEOUT] Simulation exceeded 10000 cycles. Aborting.");
            $finish;
        end
    end

    // ----------------------------------------------------------
    // Helper tasks
    // ----------------------------------------------------------

    // AXI4 single-beat write
    task axi_write;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        begin
            // Drive AW channel
            @(negedge clk);
            s00_awid    = id;
            s00_awaddr  = addr;
            s00_awlen   = 8'h00;          // 1 beat
            s00_awsize  = 3'b010;         // 4 bytes
            s00_awburst = 2'b01;          // INCR
            s00_awlock  = 1'b0;
            s00_awcache = 4'b0000;
            s00_awprot  = 3'b000;
            s00_awqos   = 4'b0000;
            s00_awuser  = {USER_WIDTH{1'b0}};
            s00_awvalid = 1'b1;

            // Drive W channel simultaneously
            s00_wdata  = data;
            s00_wstrb  = strb;
            s00_wlast  = 1'b1;
            s00_wuser  = {USER_WIDTH{1'b0}};
            s00_wvalid = 1'b1;

            // Wait for AW handshake
            @(posedge clk);
            while (!s00_awready) @(posedge clk);
            @(negedge clk);
            s00_awvalid = 1'b0;

            // Wait for W handshake
            @(posedge clk);
            while (!s00_wready) @(posedge clk);
            @(negedge clk);
            s00_wvalid = 1'b0;
            s00_wlast  = 1'b0;

            // Accept BRESP
            s00_bready = 1'b1;
            @(posedge clk);
            while (!s00_bvalid) @(posedge clk);
            $display("[WRITE] id=%0h addr=0x%08h data=0x%08h bresp=%0b @ t=%0t",
                     id, addr, data, s00_bresp, $time);
            @(negedge clk);
            s00_bready = 1'b0;
        end
    endtask

    // AXI4 single-beat read
    task axi_read;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        begin
            @(negedge clk);
            s00_arid    = id;
            s00_araddr  = addr;
            s00_arlen   = 8'h00;          // 1 beat
            s00_arsize  = 3'b010;         // 4 bytes
            s00_arburst = 2'b01;          // INCR
            s00_arlock  = 1'b0;
            s00_arcache = 4'b0000;
            s00_arprot  = 3'b000;
            s00_arqos   = 4'b0000;
            s00_aruser  = {USER_WIDTH{1'b0}};
            s00_arvalid = 1'b1;

            @(posedge clk);
            while (!s00_arready) @(posedge clk);
            @(negedge clk);
            s00_arvalid = 1'b0;

            // Accept read data
            s00_rready = 1'b1;
            @(posedge clk);
            while (!s00_rvalid) @(posedge clk);
            $display("[READ ] id=%0h addr=0x%08h rdata=0x%08h rresp=%0b rlast=%0b @ t=%0t",
                     id, addr, s00_rdata, s00_rresp, s00_rlast, $time);
            @(negedge clk);
            s00_rready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------
    initial begin
        // ---- Dump setup ------------------------------------------
`ifdef DUMP_FSDB
        // Verdi FSDB dump
        $fsdbDumpfile("tb_axi_interconnect_wrap_1x8.fsdb");
        $fsdbDumpvars(0, tb_axi_interconnect_wrap_1x8);
        $fsdbDumpMDA();   // dump multi-dimensional arrays if any
`else
        // VCS VPD dump (default when DUMP_FSDB not defined)
        $vcdplusfile("tb_axi_interconnect_wrap_1x8.vpd");
        $vcdplusdumpon;
        $vcdplusdumpvars(0, tb_axi_interconnect_wrap_1x8);
`endif

        // ---- Initialise master signals ---------------------------
        s00_awid    = {ID_WIDTH{1'b0}};
        s00_awaddr  = {ADDR_WIDTH{1'b0}};
        s00_awlen   = 8'h00;
        s00_awsize  = 3'b000;
        s00_awburst = 2'b00;
        s00_awlock  = 1'b0;
        s00_awcache = 4'b0000;
        s00_awprot  = 3'b000;
        s00_awqos   = 4'b0000;
        s00_awuser  = {USER_WIDTH{1'b0}};
        s00_awvalid = 1'b0;

        s00_wdata   = {DATA_WIDTH{1'b0}};
        s00_wstrb   = {STRB_WIDTH{1'b0}};
        s00_wlast   = 1'b0;
        s00_wuser   = {USER_WIDTH{1'b0}};
        s00_wvalid  = 1'b0;
        s00_bready  = 1'b0;

        s00_arid    = {ID_WIDTH{1'b0}};
        s00_araddr  = {ADDR_WIDTH{1'b0}};
        s00_arlen   = 8'h00;
        s00_arsize  = 3'b000;
        s00_arburst = 2'b00;
        s00_arlock  = 1'b0;
        s00_arcache = 4'b0000;
        s00_arprot  = 3'b000;
        s00_arqos   = 4'b0000;
        s00_aruser  = {USER_WIDTH{1'b0}};
        s00_arvalid = 1'b0;
        s00_rready  = 1'b0;

        // ---- Reset -----------------------------------------------
        rst = 1'b1;
        repeat(8) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat(4) @(posedge clk);

        $display("=== AXI Interconnect 1x8 Testbench ===");
        $display("--- Write Transactions ---");

        // Write 1: to M00 (0x0000_0010)  window: 0x0000_0000–0x0000_0FFF
        axi_write(8'h01, 32'h0000_0010, 32'hDEAD_BEEF, 4'hF);
        repeat(2) @(posedge clk);

        // Write 2: to M01 (0x0000_1020)  window: 0x0000_1000–0x0000_1FFF
        axi_write(8'h02, 32'h0000_1020, 32'hCAFE_BABE, 4'hF);
        repeat(2) @(posedge clk);

        // Write 3: to M02 (0x0000_2030)  window: 0x0000_2000–0x0000_2FFF
        axi_write(8'h03, 32'h0000_2030, 32'hA5A5_A5A5, 4'hF);
        repeat(2) @(posedge clk);

        $display("--- Read Transactions ---");

        // Read 1: from M03 (0x0000_3040)  window: 0x0000_3000–0x0000_3FFF  expect 0x1234_5678
        axi_read(8'h04, 32'h0000_3040);
        repeat(2) @(posedge clk);

        // Read 2: from M04 (0x0000_4050)  window: 0x0000_4000–0x0000_4FFF  expect 0xABCD_EF01
        axi_read(8'h05, 32'h0000_4050);
        repeat(4) @(posedge clk);

        $display("=== All transactions complete ===");

`ifdef DUMP_FSDB
        $fsdbDumpoff;
`else
        $vcdplusdumpoff;
`endif
        $finish;
    end

endmodule

`default_nettype wire
