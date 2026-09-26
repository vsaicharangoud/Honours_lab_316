`timescale 1ns/1ps
`default_nettype none

//======================================================================
// FULL AES AXI SYSTEM TESTBENCH
//
// Connection:
//
//   AXI MASTER
//       |
//       v
//   AXI INTERCONNECT
//       |
//       v
//   AXI AES SLAVE
//       |
//       v
//   AES REGISTER SET
//       |
//       v
//   AES-128 CORE
//
// The interconnect is instantiated as 1 master-input x 1 slave-output
// using the same axi_interconnect RTL.  This keeps the design focused
// on the AES path while using the real interconnect address decoder.
//
// AXI clock/reset:
//   clk : active clock
//   rst : ACTIVE-HIGH for AXI master/interconnect/slave
//
// AES/register-set reset:
//   aes_rst_n = ~rst
//   ACTIVE-LOW, because aes_cipher_top.v uses if(!rst).
//
// Test sequence:
//   1. Write KEY0..KEY3
//   2. Write TEXT_IN0..TEXT_IN3
//   3. Write CONTROL.START
//   4. Poll STATUS.DONE
//   5. Read TEXT_OUT0..TEXT_OUT3
//   6. Compare against expected AES-128 ciphertext
//   7. Feed ciphertext to AES inverse core
//   8. Load inverse AES key schedule
//   9. Start AES decryption
//  10. Compare decrypted plaintext against original plaintext
//
// Known-answer test:
//   KEY      = 2B7E151628AED2A6ABF7158809CF4F3C
//   PLAINTEXT= 3243F6A8885A308D313198A2E0370734
//   EXPECTED = 3925841D02DC09FBDC118597196A0B32
//
// FSDB:
//   $fsdbDumpfile("aes_axi_system.fsdb");
//   $fsdbDumpvars(0, tb_axi_aes_system);
//======================================================================

module tb_axi_aes_system;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = 4;
    localparam ID_WIDTH   = 8;

    // AXI register addresses
    localparam [31:0] ADDR_CONTROL   = 32'h0000_0000;
    localparam [31:0] ADDR_STATUS    = 32'h0000_0004;

    localparam [31:0] ADDR_KEY0      = 32'h0000_0010;
    localparam [31:0] ADDR_KEY1      = 32'h0000_0014;
    localparam [31:0] ADDR_KEY2      = 32'h0000_0018;
    localparam [31:0] ADDR_KEY3      = 32'h0000_001C;

    localparam [31:0] ADDR_TEXT_IN0  = 32'h0000_0020;
    localparam [31:0] ADDR_TEXT_IN1  = 32'h0000_0024;
    localparam [31:0] ADDR_TEXT_IN2  = 32'h0000_0028;
    localparam [31:0] ADDR_TEXT_IN3  = 32'h0000_002C;

    localparam [31:0] ADDR_TEXT_OUT0 = 32'h0000_0030;
    localparam [31:0] ADDR_TEXT_OUT1 = 32'h0000_0034;
    localparam [31:0] ADDR_TEXT_OUT2 = 32'h0000_0038;
    localparam [31:0] ADDR_TEXT_OUT3 = 32'h0000_003C;

    localparam [31:0] EXPECTED_CIPHERTEXT0 = 32'h3925_841D;
    localparam [31:0] EXPECTED_CIPHERTEXT1 = 32'h02DC_09FB;
    localparam [31:0] EXPECTED_CIPHERTEXT2 = 32'hDC11_8597;
    localparam [31:0] EXPECTED_CIPHERTEXT3 = 32'h196A_0B32;

    localparam [31:0] EXPECTED_PLAINTEXT0  = 32'h3243_F6A8;
    localparam [31:0] EXPECTED_PLAINTEXT1  = 32'h885A_308D;
    localparam [31:0] EXPECTED_PLAINTEXT2  = 32'h3131_98A2;
    localparam [31:0] EXPECTED_PLAINTEXT3  = 32'hE037_0734;

    reg clk;
    reg rst;

    //==================================================================
    // High-level AXI MASTER command interface
    //==================================================================

    reg                     wr_cmd_valid;
    wire                    wr_cmd_ready;
    reg  [ID_WIDTH-1:0]     wr_cmd_id;
    reg  [ADDR_WIDTH-1:0]   wr_cmd_addr;
    reg  [7:0]              wr_cmd_len;
    reg  [2:0]              wr_cmd_size;
    reg  [1:0]              wr_cmd_burst;

    reg                     wr_data_valid;
    wire                    wr_data_ready;
    reg  [DATA_WIDTH-1:0]   wr_data;
    reg  [STRB_WIDTH-1:0]   wr_strb;
    reg                     wr_data_last;

    wire                    wr_done;
    wire [1:0]              wr_resp;

    reg                     rd_cmd_valid;
    wire                    rd_cmd_ready;
    reg  [ID_WIDTH-1:0]     rd_cmd_id;
    reg  [ADDR_WIDTH-1:0]   rd_cmd_addr;
    reg  [7:0]              rd_cmd_len;
    reg  [2:0]              rd_cmd_size;
    reg  [1:0]              rd_cmd_burst;

    wire                    rd_data_valid;
    reg                     rd_data_ready;
    wire [DATA_WIDTH-1:0]   rd_data;
    wire [ID_WIDTH-1:0]     rd_data_id;
    wire [1:0]              rd_data_resp;
    wire                    rd_data_last;

    wire                    rd_done;
    wire [1:0]              rd_resp;

    //==================================================================
    // MASTER -> INTERCONNECT S00
    //==================================================================

    wire [ID_WIDTH-1:0]     m_awid;
    wire [ADDR_WIDTH-1:0]   m_awaddr;
    wire [7:0]              m_awlen;
    wire [2:0]              m_awsize;
    wire [1:0]              m_awburst;
    wire                    m_awlock;
    wire [3:0]              m_awcache;
    wire [2:0]              m_awprot;
    wire [3:0]              m_awqos;
    wire [3:0]              m_awregion;
    wire                    m_awvalid;
    wire                    m_awready;

    wire [DATA_WIDTH-1:0]   m_wdata;
    wire [STRB_WIDTH-1:0]   m_wstrb;
    wire                    m_wlast;
    wire                    m_wvalid;
    wire                    m_wready;

    wire [ID_WIDTH-1:0]     m_bid;
    wire [1:0]              m_bresp;
    wire                    m_bvalid;
    wire                    m_bready;

    wire [ID_WIDTH-1:0]     m_arid;
    wire [ADDR_WIDTH-1:0]   m_araddr;
    wire [7:0]              m_arlen;
    wire [2:0]              m_arsize;
    wire [1:0]              m_arburst;
    wire                    m_arlock;
    wire [3:0]              m_arcache;
    wire [2:0]              m_arprot;
    wire [3:0]              m_arqos;
    wire [3:0]              m_arregion;
    wire                    m_arvalid;
    wire                    m_arready;

    wire [ID_WIDTH-1:0]     m_rid;
    wire [DATA_WIDTH-1:0]   m_rdata;
    wire [1:0]              m_rresp;
    wire                    m_rlast;
    wire                    m_rvalid;
    wire                    m_rready;

    //==================================================================
    // INTERCONNECT -> AES SLAVE M00
    //==================================================================

    wire [ID_WIDTH-1:0]     s_awid;
    wire [ADDR_WIDTH-1:0]   s_awaddr;
    wire [7:0]              s_awlen;
    wire [2:0]              s_awsize;
    wire [1:0]              s_awburst;
    wire                    s_awlock;
    wire [3:0]              s_awcache;
    wire [2:0]              s_awprot;
    wire [3:0]              s_awqos;
    wire [3:0]              s_awregion;
    wire                    s_awvalid;
    wire                    s_awready;

    wire [DATA_WIDTH-1:0]   s_wdata;
    wire [STRB_WIDTH-1:0]   s_wstrb;
    wire                    s_wlast;
    wire                    s_wvalid;
    wire                    s_wready;

    wire [ID_WIDTH-1:0]     s_bid;
    wire [1:0]              s_bresp;
    wire                    s_bvalid;
    wire                    s_bready;

    wire [ID_WIDTH-1:0]     s_arid;
    wire [ADDR_WIDTH-1:0]   s_araddr;
    wire [7:0]              s_arlen;
    wire [2:0]              s_arsize;
    wire [1:0]              s_arburst;
    wire                    s_arlock;
    wire [3:0]              s_arcache;
    wire [2:0]              s_arprot;
    wire [3:0]              s_arqos;
    wire [3:0]              s_arregion;
    wire                    s_arvalid;
    wire                    s_arready;

    wire [ID_WIDTH-1:0]     s_rid;
    wire [DATA_WIDTH-1:0]   s_rdata;
    wire [1:0]              s_rresp;
    wire                    s_rlast;
    wire                    s_rvalid;
    wire                    s_rready;

    //==================================================================
    // REGISTER SET INTERFACE
    //==================================================================

    wire                    reg_wr_en;
    wire [ADDR_WIDTH-1:0]   reg_wr_addr;
    wire [DATA_WIDTH-1:0]   reg_wr_data;
    wire [STRB_WIDTH-1:0]   reg_wr_strb;

    wire                    reg_rd_en;
    wire [ADDR_WIDTH-1:0]   reg_rd_addr;
    wire [DATA_WIDTH-1:0]   reg_rd_data;

    wire [127:0]            aes_key;
    wire [127:0]            aes_text_in;
    wire                    aes_ld;
    wire [127:0]            aes_text_out;
    wire                    aes_done;

    //==================================================================
    // AES DECRYPTION SIGNALS
    // These are intentionally exposed at TB level for easy Verdi debug.
    //==================================================================
    reg                     dec_kld;
    reg                     dec_ld;
    wire                    dec_done;
    wire                    dec_key_done;
    wire [127:0]            dec_key;
    wire [127:0]            dec_text_out;

    // Hold the AXI-read ciphertext in a stable TB register before
    // starting the inverse AES core.  Do not drive the decrypt input
    // directly from aes_text_out because the encryption core/register
    // timing can change that signal after DONE.
    reg  [127:0]            ciphertext_for_decrypt;
    wire [127:0]            dec_text_in;

    assign dec_key     = aes_key;
    assign dec_text_in = ciphertext_for_decrypt;

    wire aes_rst_n;

    assign aes_rst_n = ~rst;

    //==================================================================
    // AXI MASTER
    //==================================================================

    axi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) u_axi_master (

        .clk(clk),
        .rst(rst),

        .wr_cmd_valid(wr_cmd_valid),
        .wr_cmd_ready(wr_cmd_ready),
        .wr_cmd_id(wr_cmd_id),
        .wr_cmd_addr(wr_cmd_addr),
        .wr_cmd_len(wr_cmd_len),
        .wr_cmd_size(wr_cmd_size),
        .wr_cmd_burst(wr_cmd_burst),

        .wr_data_valid(wr_data_valid),
        .wr_data_ready(wr_data_ready),
        .wr_data(wr_data),
        .wr_strb(wr_strb),
        .wr_data_last(wr_data_last),

        .wr_done(wr_done),
        .wr_resp(wr_resp),

        .rd_cmd_valid(rd_cmd_valid),
        .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_id(rd_cmd_id),
        .rd_cmd_addr(rd_cmd_addr),
        .rd_cmd_len(rd_cmd_len),
        .rd_cmd_size(rd_cmd_size),
        .rd_cmd_burst(rd_cmd_burst),

        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready),
        .rd_data(rd_data),
        .rd_data_id(rd_data_id),
        .rd_data_resp(rd_data_resp),
        .rd_data_last(rd_data_last),

        .rd_done(rd_done),
        .rd_resp(rd_resp),

        .m_axi_awid(m_awid),
        .m_axi_awaddr(m_awaddr),
        .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst),
        .m_axi_awlock(m_awlock),
        .m_axi_awcache(m_awcache),
        .m_axi_awprot(m_awprot),
        .m_axi_awqos(m_awqos),
        .m_axi_awregion(m_awregion),
        .m_axi_awuser(),
        .m_axi_awvalid(m_awvalid),
        .m_axi_awready(m_awready),

        .m_axi_wdata(m_wdata),
        .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast),
        .m_axi_wuser(),
        .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),

        .m_axi_bid(m_bid),
        .m_axi_bresp(m_bresp),
        .m_axi_buser({1{1'b0}}),
        .m_axi_bvalid(m_bvalid),
        .m_axi_bready(m_bready),

        .m_axi_arid(m_arid),
        .m_axi_araddr(m_araddr),
        .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize),
        .m_axi_arburst(m_arburst),
        .m_axi_arlock(m_arlock),
        .m_axi_arcache(m_arcache),
        .m_axi_arprot(m_arprot),
        .m_axi_arqos(m_arqos),
        .m_axi_arregion(m_arregion),
        .m_axi_aruser(),
        .m_axi_arvalid(m_arvalid),
        .m_axi_arready(m_arready),

        .m_axi_rid(m_rid),
        .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast),
        .m_axi_ruser({1{1'b0}}),
        .m_axi_rvalid(m_rvalid),
        .m_axi_rready(m_rready)
    );

    //==================================================================
    // AXI INTERCONNECT
    //
    // S_COUNT=1: one AXI master input
    // M_COUNT=1: one AXI AES slave output
    //
    // AES register window is therefore:
    //   base = 0x0000_0000
    //   width = 24 bits
    //   range = 0x0000_0000 - 0x00FF_FFFF
    //==================================================================

    axi_interconnect #(
        .S_COUNT(1),
        .M_COUNT(1),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .AWUSER_ENABLE(0),
        .WUSER_ENABLE(0),
        .BUSER_ENABLE(0),
        .ARUSER_ENABLE(0),
        .RUSER_ENABLE(0),
        .FORWARD_ID(0),
        .M_REGIONS(1),
        .M_BASE_ADDR(32'h0000_0000),
        .M_ADDR_WIDTH({32'd24}),
        .M_CONNECT_READ(1'b1),
        .M_CONNECT_WRITE(1'b1),
        .M_SECURE(1'b0)
    ) u_axi_interconnect (

        .clk(clk),
        .rst(rst),

        // S00 AXI interface
        .s_axi_awid(m_awid),
        .s_axi_awaddr(m_awaddr),
        .s_axi_awlen(m_awlen),
        .s_axi_awsize(m_awsize),
        .s_axi_awburst(m_awburst),
        .s_axi_awlock(m_awlock),
        .s_axi_awcache(m_awcache),
        .s_axi_awprot(m_awprot),
        .s_axi_awqos(m_awqos),
        .s_axi_awuser(1'b0),
        .s_axi_awvalid(m_awvalid),
        .s_axi_awready(m_awready),

        .s_axi_wdata(m_wdata),
        .s_axi_wstrb(m_wstrb),
        .s_axi_wlast(m_wlast),
        .s_axi_wuser(1'b0),
        .s_axi_wvalid(m_wvalid),
        .s_axi_wready(m_wready),

        .s_axi_bid(m_bid),
        .s_axi_bresp(m_bresp),
        .s_axi_buser(),
        .s_axi_bvalid(m_bvalid),
        .s_axi_bready(m_bready),

        .s_axi_arid(m_arid),
        .s_axi_araddr(m_araddr),
        .s_axi_arlen(m_arlen),
        .s_axi_arsize(m_arsize),
        .s_axi_arburst(m_arburst),
        .s_axi_arlock(m_arlock),
        .s_axi_arcache(m_arcache),
        .s_axi_arprot(m_arprot),
        .s_axi_arqos(m_arqos),
        .s_axi_aruser(1'b0),
        .s_axi_arvalid(m_arvalid),
        .s_axi_arready(m_arready),

        .s_axi_rid(m_rid),
        .s_axi_rdata(m_rdata),
        .s_axi_rresp(m_rresp),
        .s_axi_rlast(m_rlast),
        .s_axi_ruser(),
        .s_axi_rvalid(m_rvalid),
        .s_axi_rready(m_rready),

        // M00 AXI interface
        .m_axi_awid(s_awid),
        .m_axi_awaddr(s_awaddr),
        .m_axi_awlen(s_awlen),
        .m_axi_awsize(s_awsize),
        .m_axi_awburst(s_awburst),
        .m_axi_awlock(s_awlock),
        .m_axi_awcache(s_awcache),
        .m_axi_awprot(s_awprot),
        .m_axi_awqos(s_awqos),
        .m_axi_awregion(s_awregion),
        .m_axi_awuser(),
        .m_axi_awvalid(s_awvalid),
        .m_axi_awready(s_awready),

        .m_axi_wdata(s_wdata),
        .m_axi_wstrb(s_wstrb),
        .m_axi_wlast(s_wlast),
        .m_axi_wuser(),
        .m_axi_wvalid(s_wvalid),
        .m_axi_wready(s_wready),

        .m_axi_bid(s_bid),
        .m_axi_bresp(s_bresp),
        .m_axi_buser(1'b0),
        .m_axi_bvalid(s_bvalid),
        .m_axi_bready(s_bready),

        .m_axi_arid(s_arid),
        .m_axi_araddr(s_araddr),
        .m_axi_arlen(s_arlen),
        .m_axi_arsize(s_arsize),
        .m_axi_arburst(s_arburst),
        .m_axi_arlock(s_arlock),
        .m_axi_arcache(s_arcache),
        .m_axi_arprot(s_arprot),
        .m_axi_arqos(s_arqos),
        .m_axi_arregion(s_arregion),
        .m_axi_aruser(),
        .m_axi_arvalid(s_arvalid),
        .m_axi_arready(s_arready),

        .m_axi_rid(s_rid),
        .m_axi_rdata(s_rdata),
        .m_axi_rresp(s_rresp),
        .m_axi_rlast(s_rlast),
        .m_axi_ruser(),
        .m_axi_rvalid(s_rvalid),
        .m_axi_rready(s_rready)
    );

    //==================================================================
    // AXI AES SLAVE
    //==================================================================

    axi_aes_slave #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) u_axi_aes_slave (

        .clk(clk),
        .rst(rst),

        .s_axi_awid(s_awid),
        .s_axi_awaddr(s_awaddr),
        .s_axi_awlen(s_awlen),
        .s_axi_awsize(s_awsize),
        .s_axi_awburst(s_awburst),
        .s_axi_awlock(s_awlock),
        .s_axi_awcache(s_awcache),
        .s_axi_awprot(s_awprot),
        .s_axi_awqos(s_awqos),
        .s_axi_awregion(s_awregion),
        .s_axi_awuser(1'b0),
        .s_axi_awvalid(s_awvalid),
        .s_axi_awready(s_awready),

        .s_axi_wdata(s_wdata),
        .s_axi_wstrb(s_wstrb),
        .s_axi_wlast(s_wlast),
        .s_axi_wuser(1'b0),
        .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready),

        .s_axi_bid(s_bid),
        .s_axi_bresp(s_bresp),
        .s_axi_buser(),
        .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready),

        .s_axi_arid(s_arid),
        .s_axi_araddr(s_araddr),
        .s_axi_arlen(s_arlen),
        .s_axi_arsize(s_arsize),
        .s_axi_arburst(s_arburst),
        .s_axi_arlock(s_arlock),
        .s_axi_arcache(s_arcache),
        .s_axi_arprot(s_arprot),
        .s_axi_arqos(s_arqos),
        .s_axi_arregion(s_arregion),
        .s_axi_aruser(1'b0),
        .s_axi_arvalid(s_arvalid),
        .s_axi_arready(s_arready),

        .s_axi_rid(s_rid),
        .s_axi_rdata(s_rdata),
        .s_axi_rresp(s_rresp),
        .s_axi_rlast(s_rlast),
        .s_axi_ruser(),
        .s_axi_rvalid(s_rvalid),
        .s_axi_rready(s_rready),

        .reg_wr_en(reg_wr_en),
        .reg_wr_addr(reg_wr_addr),
        .reg_wr_data(reg_wr_data),
        .reg_wr_strb(reg_wr_strb),

        .reg_rd_en(reg_rd_en),
        .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data)
    );

    //==================================================================
    // AES REGISTER SET
    //==================================================================

    aes_register_set #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_aes_register_set (

        .clk(clk),
        .rst(aes_rst_n),

        .reg_wr_en(reg_wr_en),
        .reg_wr_addr(reg_wr_addr),
        .reg_wr_data(reg_wr_data),
        .reg_wr_strb(reg_wr_strb),

        .reg_rd_en(reg_rd_en),
        .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data),

        .aes_key(aes_key),
        .aes_text_in(aes_text_in),
        .aes_ld(aes_ld),

        .aes_text_out(aes_text_out),
        .aes_done(aes_done)
    );

    //==================================================================
    // AES CORE
    //==================================================================

    aes_cipher_top u_aes_cipher (

        .clk(clk),
        .rst(aes_rst_n),
        .ld(aes_ld),
        .done(aes_done),
        .key(aes_key),
        .text_in(aes_text_in),
        .text_out(aes_text_out)
    );

    //==================================================================
    // AES INVERSE / DECRYPTION CORE
    //
    // The encryption result is directly connected to the inverse core.
    // dec_kld loads the inverse key schedule.
    // dec_ld starts the inverse cipher operation.
    // dec_done indicates decryption completion.
    //==================================================================

    assign dec_key_done = u_aes_inv_cipher.kdone;

    aes_inv_cipher_top u_aes_inv_cipher (

        .clk(clk),
        .rst(aes_rst_n),
        .kld(dec_kld),
        .ld(dec_ld),
        .done(dec_done),
        .key(dec_key),
        .text_in(dec_text_in),
        .text_out(dec_text_out)
    );

    //==================================================================
    // CLOCK
    //==================================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //==================================================================
    // RESET / INITIALIZATION
    //==================================================================

    initial begin

        rst = 1'b1;

        dec_kld = 1'b0;
        dec_ld  = 1'b0;
        ciphertext_for_decrypt = 128'h0;

        wr_cmd_valid = 1'b0;
        wr_cmd_id    = 8'h00;
        wr_cmd_addr  = 32'h0;
        wr_cmd_len   = 8'd0;
        wr_cmd_size  = 3'd2;
        wr_cmd_burst = 2'b01;

        wr_data_valid = 1'b0;
        wr_data       = 32'h0;
        wr_strb       = 4'hF;
        wr_data_last  = 1'b1;

        rd_cmd_valid = 1'b0;
        rd_cmd_id    = 8'h00;
        rd_cmd_addr  = 32'h0;
        rd_cmd_len   = 8'd0;
        rd_cmd_size  = 3'd2;
        rd_cmd_burst = 2'b01;

        rd_data_ready = 1'b0;

        #30;

        rst = 1'b0;

        $display("");
        $display("================================================================");
        $display(" RESET RELEASED - STARTING FULL AXI -> AES TEST");
        $display("================================================================");
        $display("");

        run_aes_test;

        $display("");
        $display("================================================================");
        $display(" TESTBENCH FINISHED");
        $display("================================================================");
        $display("");

        #50;
        $finish;
    end

    //==================================================================
    // COMPLETE AES TEST
    //==================================================================

    task run_aes_test;

        reg [31:0] status;
        reg [31:0] result0;
        reg [31:0] result1;
        reg [31:0] result2;
        reg [31:0] result3;
        integer poll_count;

        begin

            //==========================================================
            // KEY
            //==========================================================

            $display("################################################################");
            $display(" STEP 1 : WRITE AES KEY");
            $display("################################################################");

            axi_write(8'h01, ADDR_KEY0, 32'h2B7E_1516);
            axi_write(8'h02, ADDR_KEY1, 32'h28AE_D2A6);
            axi_write(8'h03, ADDR_KEY2, 32'hABF7_1588);
            axi_write(8'h04, ADDR_KEY3, 32'h09CF_4F3C);

            $display("KEY = 2B7E151628AED2A6ABF7158809CF4F3C");
            $display("");

            //==========================================================
            // PLAINTEXT
            //==========================================================

            $display("################################################################");
            $display(" STEP 2 : WRITE PLAINTEXT");
            $display("################################################################");

            axi_write(8'h05, ADDR_TEXT_IN0, 32'h3243_F6A8);
            axi_write(8'h06, ADDR_TEXT_IN1, 32'h885A_308D);
            axi_write(8'h07, ADDR_TEXT_IN2, 32'h3131_98A2);
            axi_write(8'h08, ADDR_TEXT_IN3, 32'hE037_0734);

            $display("PLAINTEXT = 3243F6A8885A308D313198A2E0370734");
            $display("");

            //==========================================================
            // START
            //==========================================================

            $display("################################################################");
            $display(" STEP 3 : START AES ENCRYPTION");
            $display("################################################################");

            axi_write(8'h09, ADDR_CONTROL, 32'h0000_0001);

            $display("[%0t] CONTROL.START written = 1", $time);
            $display("AES encryption is now running...");
            $display("");

            //==========================================================
            // POLL STATUS
            //==========================================================

            $display("################################################################");
            $display(" STEP 4 : POLL STATUS.DONE");
            $display("################################################################");

            status = 32'h0;
            poll_count = 0;

            while (!status[0] && poll_count < 100) begin

                axi_read(8'h20 + poll_count[7:0], ADDR_STATUS, status);

                $display("[%0t] STATUS = 0x%08h | BUSY=%b DONE=%b",
                         $time,
                         status,
                         status[1],
                         status[0]);

                poll_count = poll_count + 1;

            end

            if (!status[0]) begin
                $display("");
                $display("ERROR: AES DONE was not observed.");
                $display("Check AES core, aes_ld, aes_done and register set.");
                $finish;
            end

            $display("");
            $display("AES DONE = 1");
            $display("");

            //==========================================================
            // READ RESULT
            //==========================================================

            $display("################################################################");
            $display(" STEP 5 : READ AES CIPHERTEXT");
            $display("################################################################");

            axi_read(8'h31, ADDR_TEXT_OUT0, result0);
            axi_read(8'h32, ADDR_TEXT_OUT1, result1);
            axi_read(8'h33, ADDR_TEXT_OUT2, result2);
            axi_read(8'h34, ADDR_TEXT_OUT3, result3);

            // Capture exactly what was returned through AXI.
            // This is the ciphertext that must be presented to the
            // inverse AES core.
            ciphertext_for_decrypt =
                {result0, result1, result2, result3};

            $display("");
            $display("ACTUAL CIPHERTEXT:");
            $display("  %08h%08h%08h%08h",
                     result0, result1, result2, result3);

            $display("");
            $display("EXPECTED CIPHERTEXT:");
            $display("  %08h%08h%08h%08h",
                     EXPECTED_CIPHERTEXT0,
                     EXPECTED_CIPHERTEXT1,
                     EXPECTED_CIPHERTEXT2,
                     EXPECTED_CIPHERTEXT3);

            //==========================================================
            // FINAL CHECK
            //==========================================================

            $display("");
            $display("################################################################");

            if ((result0 == EXPECTED_CIPHERTEXT0) &&
                (result1 == EXPECTED_CIPHERTEXT1) &&
                (result2 == EXPECTED_CIPHERTEXT2) &&
                (result3 == EXPECTED_CIPHERTEXT3)) begin

                $display("                 *** AES ENCRYPTION PASS ***");
                $display("################################################################");

                // Encryption passed. Now verify the inverse/decryption core.
                run_aes_decrypt_test;

            end
            else begin

                $display("                 *** AES TEST FAIL ***");
                $display("################################################################");

                $display("Mismatch detected.");
                $display("Check KEY/TEXT_IN register mapping and AES timing.");
            end

        end
    endtask

    //==================================================================
    // AES DECRYPTION TEST
    //
    // Input to the inverse core:
    //   key       = aes_key
    //   ciphertext= ciphertext_for_decrypt
    //
    // ciphertext_for_decrypt is captured from the four AXI TEXT_OUT
    // reads, so it remains stable throughout the inverse operation.
    //
    // Expected output:
    //   plaintext = 3243F6A8885A308D313198A2E0370734
    //==================================================================

    task run_aes_decrypt_test;

        reg [127:0] expected_plaintext;

        begin

            expected_plaintext =
                {EXPECTED_PLAINTEXT0, EXPECTED_PLAINTEXT1,
                 EXPECTED_PLAINTEXT2, EXPECTED_PLAINTEXT3};

            $display("");
            $display("################################################################");
            $display(" STEP 6 : AES DECRYPTION");
            $display("################################################################");

            $display("");
            $display("DECRYPTION KEY:");
            $display("  %032h", dec_key);

            $display("");
            $display("CIPHERTEXT INPUT TO INVERSE CORE:");
            $display("  %032h", dec_text_in);

            $display("");
            $display("EXPECTED/AXI-READ CIPHERTEXT:");
            $display("  %032h",
                     {EXPECTED_CIPHERTEXT0, EXPECTED_CIPHERTEXT1,
                      EXPECTED_CIPHERTEXT2, EXPECTED_CIPHERTEXT3});

            // Make sure the inverse core is being fed the exact
            // ciphertext produced and read through the AXI path.
            if (dec_text_in !=
                {EXPECTED_CIPHERTEXT0, EXPECTED_CIPHERTEXT1,
                 EXPECTED_CIPHERTEXT2, EXPECTED_CIPHERTEXT3}) begin
                $display("");
                $display("ERROR: Decryption input ciphertext is incorrect.");
                $display("Check TEXT_OUT AXI reads and ciphertext capture.");
                $display("Actual   = %032h", dec_text_in);
                $display("Expected = %032h",
                         {EXPECTED_CIPHERTEXT0, EXPECTED_CIPHERTEXT1,
                          EXPECTED_CIPHERTEXT2, EXPECTED_CIPHERTEXT3});
                $finish;
            end

            //==========================================================
            // LOAD DECRYPTION KEY SCHEDULE
            //==========================================================

            $display("");
            $display("[%0t] DECRYPTION : KLD asserted", $time);

            dec_kld = 1'b1;

            @(posedge clk);

            dec_kld = 1'b0;

            $display("[%0t] DECRYPTION : KLD deasserted, waiting for key schedule",
                     $time);

            // aes_inv_cipher_top asserts its internal kdone after the
            // inverse key buffer has been filled.
            wait (dec_key_done == 1'b1);

            $display("[%0t] DECRYPTION : KEY LOAD DONE (kdone=1)", $time);

            //==========================================================
            // START DECRYPTION
            //==========================================================

            @(posedge clk);

            $display("[%0t] DECRYPTION : LD/START asserted", $time);

            dec_ld = 1'b1;

            @(posedge clk);

            dec_ld = 1'b0;

            $display("[%0t] DECRYPTION : LD/START deasserted", $time);

            //==========================================================
            // WAIT FOR DECRYPTION DONE
            //==========================================================

            wait (dec_done == 1'b1);

            $display("");
            $display("[%0t] DECRYPTION : DONE asserted", $time);
            $display("[%0t] DECRYPTION : TEXT_OUT = 0x%032h",
                     $time, dec_text_out);

            $display("");
            $display("DECRYPTED PLAINTEXT:");
            $display("  %032h", dec_text_out);

            $display("");
            $display("EXPECTED PLAINTEXT:");
            $display("  %032h", expected_plaintext);

            //==========================================================
            // DECRYPTION CHECK
            //==========================================================

            $display("");
            $display("################################################################");

            if (dec_text_out == expected_plaintext) begin

                $display("              *** AES DECRYPTION PASS ***");
                $display("################################################################");

            end
            else begin

                $display("              *** AES DECRYPTION FAIL ***");
                $display("################################################################");
                $display("Expected = %032h", expected_plaintext);
                $display("Actual   = %032h", dec_text_out);

            end

        end
    endtask

    //==================================================================
    // AXI WRITE TASK
    //==================================================================

    task axi_write;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;

        begin

            $display("");
            $display("[WRITE REQUEST]");
            $display("  ID   = 0x%02h", id);
            $display("  ADDR = 0x%08h", addr);
            $display("  DATA = 0x%08h", data);

            // Present high-level write command.
            @(posedge clk);

            wr_cmd_id    <= id;
            wr_cmd_addr  <= addr;
            wr_cmd_len   <= 8'd0;
            wr_cmd_size  <= 3'd2;
            wr_cmd_burst <= 2'b01;
            wr_cmd_valid <= 1'b1;

            while (!wr_cmd_ready)
                @(posedge clk);

            @(posedge clk);
            wr_cmd_valid <= 1'b0;

            $display("[%0t] AXI MASTER : WRITE COMMAND accepted", $time);

            // Present write data.
            wr_data       <= data;
            wr_strb       <= 4'hF;
            wr_data_last  <= 1'b1;
            wr_data_valid <= 1'b1;

            while (!wr_data_ready)
                @(posedge clk);

            @(posedge clk);
            wr_data_valid <= 1'b0;

            $display("[%0t] AXI MASTER : WDATA accepted", $time);
            $display("       WDATA = 0x%08h WSTRB = 0x%1h WLAST = 1",
                     data, 4'hF);

            // Wait for B response.
            while (!wr_done)
                @(posedge clk);

            if (wr_resp == 2'b00)
                $display("[%0t] AXI MASTER : BRESP = OKAY -> WRITE PASS",
                         $time);
            else
                $display("[%0t] AXI MASTER : BRESP = %b -> WRITE FAIL",
                         $time, wr_resp);

        end
    endtask

    //==================================================================
    // AXI READ TASK
    //==================================================================

    task axi_read;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;

        begin

            data = 32'h0;

            $display("");
            $display("[READ REQUEST]");
            $display("  ID   = 0x%02h", id);
            $display("  ADDR = 0x%08h", addr);

            @(posedge clk);

            rd_cmd_id    <= id;
            rd_cmd_addr  <= addr;
            rd_cmd_len   <= 8'd0;
            rd_cmd_size  <= 3'd2;
            rd_cmd_burst <= 2'b01;
            rd_cmd_valid <= 1'b1;

            while (!rd_cmd_ready)
                @(posedge clk);

            @(posedge clk);
            rd_cmd_valid <= 1'b0;

            $display("[%0t] AXI MASTER : READ COMMAND accepted", $time);

            rd_data_ready <= 1'b1;

            while (!rd_data_valid)
                @(posedge clk);

            data = rd_data;

            $display("[%0t] AXI MASTER : RDATA received", $time);
            $display("       RID   = 0x%02h", rd_data_id);
            $display("       RDATA = 0x%08h", rd_data);
            $display("       RRESP = %b", rd_data_resp);
            $display("       RLAST = %b", rd_data_last);

            if ((rd_data_resp == 2'b00) && rd_data_last)
                $display("       READ PASS");
            else
                $display("       READ FAIL");

            rd_data_ready <= 1'b0;

            while (!rd_done)
                @(posedge clk);

        end
    endtask

    //==================================================================
    // CHANNEL MONITOR
    //
    // These messages make it easy to correlate console output with
    // the Verdi waveform.
    //==================================================================

    always @(posedge clk) begin

        if (!rst) begin

            if (m_awvalid && m_awready)
                $display("[%0t] CHANNEL AW : MASTER -> INTERCONNECT  ADDR=0x%08h ID=0x%02h",
                         $time, m_awaddr, m_awid);

            if (m_wvalid && m_wready)
                $display("[%0t] CHANNEL W  : MASTER -> INTERCONNECT  DATA=0x%08h LAST=%b",
                         $time, m_wdata, m_wlast);

            if (m_bvalid && m_bready)
                $display("[%0t] CHANNEL B  : INTERCONNECT -> MASTER  RESP=%b ID=0x%02h",
                         $time, m_bresp, m_bid);

            if (m_arvalid && m_arready)
                $display("[%0t] CHANNEL AR : MASTER -> INTERCONNECT  ADDR=0x%08h ID=0x%02h",
                         $time, m_araddr, m_arid);

            if (m_rvalid && m_rready)
                $display("[%0t] CHANNEL R  : INTERCONNECT -> MASTER  DATA=0x%08h RESP=%b LAST=%b",
                         $time, m_rdata, m_rresp, m_rlast);

            if (reg_wr_en)
                $display("[%0t] REGISTER WRITE : ADDR=0x%08h DATA=0x%08h STRB=0x%1h",
                         $time, reg_wr_addr, reg_wr_data, reg_wr_strb);

            if (aes_ld)
                $display("[%0t] AES CORE : LD/START asserted", $time);

            if (aes_done)
                $display("[%0t] AES CORE : DONE asserted, TEXT_OUT=0x%032h",
                         $time, aes_text_out);

            if (dec_kld)
                $display("[%0t] AES DECRYPT CORE : KLD asserted", $time);

            if (dec_ld)
                $display("[%0t] AES DECRYPT CORE : LD/START asserted, CIPHERTEXT=0x%032h",
                         $time, dec_text_in);

            if (dec_key_done)
                $display("[%0t] AES DECRYPT CORE : KDONE asserted", $time);

            if (dec_done)
                $display("[%0t] AES DECRYPT CORE : DONE asserted, PLAINTEXT=0x%032h",
                         $time, dec_text_out);

        end

    end

    //==================================================================
    // TIMEOUT
    //==================================================================

    initial begin
        #20000;
        $display("");
        $display("ERROR: GLOBAL TESTBENCH TIMEOUT");
        $display("Simulation stopped after 20 us.");
        $finish;
    end

    //==================================================================
    // FSDB WAVEFORM
    //
    // No VCD is required for Verdi. This directly creates the FSDB.
    // ciphertext_for_decrypt is also dumped because it is inside the TB
    // hierarchy and is the stable decryption input.
    //==================================================================

    initial begin
        $fsdbDumpfile("aes_axi_system.fsdb");
        $fsdbDumpvars(0, tb_axi_aes_system);
    end

endmodule

`default_nettype wire