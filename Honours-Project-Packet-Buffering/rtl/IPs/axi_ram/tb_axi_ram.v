/*
 * ============================================================================
 * File: tb_axi_ram.v
 * Project: Reliable Data Transport System SoC
 * Description: Self-checking Testbench for AXI4 RAM Memory IP
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

module tb_axi_ram;

    parameter DATA_WIDTH    = 32;
    parameter ADDR_WIDTH    = 32;
    parameter ID_WIDTH      = 8;
    parameter STRB_WIDTH    = 4;
    parameter USER_WIDTH    = 1;
    parameter MEM_ADDR_BITS = 16; // 64KB

    reg clk;
    reg rst;

    reg  [ID_WIDTH-1:0]   s_axi_awid;
    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg  [7:0]            s_axi_awlen;
    reg  [2:0]            s_axi_awsize;
    reg  [1:0]            s_axi_awburst;
    reg                   s_axi_awlock;
    reg  [3:0]            s_axi_awcache;
    reg  [2:0]            s_axi_awprot;
    reg  [3:0]            s_axi_awqos;
    reg  [3:0]            s_axi_awregion;
    reg  [USER_WIDTH-1:0] s_axi_awuser;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    reg  [DATA_WIDTH-1:0] s_axi_wdata;
    reg  [STRB_WIDTH-1:0] s_axi_wstrb;
    reg                   s_axi_wlast;
    reg  [USER_WIDTH-1:0] s_axi_wuser;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;

    wire [ID_WIDTH-1:0]   s_axi_bid;
    wire [1:0]            s_axi_bresp;
    wire [USER_WIDTH-1:0] s_axi_buser;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;

    reg  [ID_WIDTH-1:0]   s_axi_arid;
    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg  [7:0]            s_axi_arlen;
    reg  [2:0]            s_axi_arsize;
    reg  [1:0]            s_axi_arburst;
    reg                   s_axi_arlock;
    reg  [3:0]            s_axi_arcache;
    reg  [2:0]            s_axi_arprot;
    reg  [3:0]            s_axi_arqos;
    reg  [3:0]            s_axi_arregion;
    reg  [USER_WIDTH-1:0] s_axi_aruser;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    wire [ID_WIDTH-1:0]   s_axi_rid;
    wire [DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rlast;
    wire [USER_WIDTH-1:0] s_axi_ruser;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    axi_ram #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .ID_WIDTH       (ID_WIDTH),
        .STRB_WIDTH     (STRB_WIDTH),
        .USER_WIDTH     (USER_WIDTH),
        .MEM_ADDR_BITS  (MEM_ADDR_BITS)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awlock   (s_axi_awlock),
        .s_axi_awcache  (s_axi_awcache),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awqos    (s_axi_awqos),
        .s_axi_awregion (s_axi_awregion),
        .s_axi_awuser   (s_axi_awuser),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wuser    (s_axi_wuser),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_buser    (s_axi_buser),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arlock   (s_axi_arlock),
        .s_axi_arcache  (s_axi_arcache),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arqos    (s_axi_arqos),
        .s_axi_arregion (s_axi_arregion),
        .s_axi_aruser   (s_axi_aruser),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rid      (s_axi_rid),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_ruser    (s_axi_ruser),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Single Word Write Task
    task axi_single_write(input [31:0] addr, input [31:0] data, input [3:0] strb);
    begin
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd0;
        s_axi_awsize  <= 3'd2;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= strb;
        s_axi_wvalid  <= 1'b1;
        s_axi_wlast   <= 1'b1;
        s_axi_bready  <= 1'b1;

        fork
            begin
                wait(s_axi_awready);
                @(posedge clk);
                s_axi_awvalid <= 1'b0;
            end
            begin
                wait(s_axi_wready);
                @(posedge clk);
                s_axi_wvalid <= 1'b0;
                s_axi_wlast  <= 1'b0;
            end
        join

        wait(s_axi_bvalid);
        @(posedge clk);
        s_axi_bready <= 1'b0;
        @(posedge clk);
    end
    endtask

    // Single Word Read Task
    task axi_single_read(input [31:0] addr, output [31:0] data);
    begin
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd0;
        s_axi_arsize  <= 3'd2;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        wait(s_axi_arready);
        @(posedge clk);
        s_axi_arvalid <= 1'b0;

        wait(s_axi_rvalid);
        data = s_axi_rdata;
        @(posedge clk);
        s_axi_rready <= 1'b0;
        @(posedge clk);
    end
    endtask

    reg [31:0] rd_data;

    initial begin
        rst           = 1'b1;
        s_axi_awid    = 8'd1;
        s_axi_awaddr  = 32'd0;
        s_axi_awlen   = 8'd0;
        s_axi_awsize  = 3'd2;
        s_axi_awburst = 2'd1; // INCR
        s_axi_awlock  = 1'b0;
        s_axi_awcache = 4'd0;
        s_axi_awprot  = 3'd0;
        s_axi_awqos   = 4'd0;
        s_axi_awregion= 4'd0;
        s_axi_awuser  = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'd0;
        s_axi_wlast   = 1'b0;
        s_axi_wuser   = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_arid    = 8'd2;
        s_axi_araddr  = 32'd0;
        s_axi_arlen   = 8'd0;
        s_axi_arsize  = 3'd2;
        s_axi_arburst = 2'd1; // INCR
        s_axi_arlock  = 1'b0;
        s_axi_arcache = 4'd0;
        s_axi_arprot  = 3'd0;
        s_axi_arqos   = 4'd0;
        s_axi_arregion= 4'd0;
        s_axi_aruser  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        $display("================================================================");
        $display(" Starting AXI4 RAM IP (64KB) Verification Testbench ");
        $display("================================================================");

        #40;
        @(posedge clk);
        rst = 1'b0;
        #20;

        // TEST 1: Single 32-bit Word Write and Readback
        $display("[TEST 1] Single Word Write and Readback...");
        axi_single_write(32'h0000_0100, 32'h1234_5678, 4'hF);
        axi_single_read(32'h0000_0100, rd_data);
        if (rd_data == 32'h1234_5678) begin
            $display("  -> Word write/read PASS: 0x%08x", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Word write/read FAIL: 0x%08x (expected 0x12345678)", rd_data);
            fail_count = fail_count + 1;
        end

        // TEST 2: Byte Strobe Masking
        $display("[TEST 2] Testing Byte Strobe Masking (Modify byte 1 only)...");
        axi_single_write(32'h0000_0100, 32'h0000_AA00, 4'b0010); // Update byte 1 only
        axi_single_read(32'h0000_0100, rd_data);
        if (rd_data == 32'h1234_AA78) begin
            $display("  -> Byte strobe write PASS: 0x%08x", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Byte strobe write FAIL: 0x%08x (expected 0x1234AA78)", rd_data);
            fail_count = fail_count + 1;
        end

        // TEST 3: Multi-beat INCR Burst Write & Burst Read (4 words)
        $display("[TEST 3] Multi-Beat INCR Burst Write and Read (4 words)...");
        @(posedge clk);
        s_axi_awaddr  <= 32'h0000_0200;
        s_axi_awlen   <= 8'd3; // 4 beats: 0, 1, 2, 3
        s_axi_awsize  <= 3'd2;
        s_axi_awvalid <= 1'b1;
        s_axi_bready  <= 1'b1;

        wait(s_axi_awready);
        @(posedge clk);
        s_axi_awvalid <= 1'b0;

        // Beat 0
        s_axi_wdata  <= 32'hA0A0_0000;
        s_axi_wstrb  <= 4'hF;
        s_axi_wlast  <= 1'b0;
        s_axi_wvalid <= 1'b1;
        @(posedge clk);

        // Beat 1
        s_axi_wdata  <= 32'hA1A1_1111;
        @(posedge clk);

        // Beat 2
        s_axi_wdata  <= 32'hA2A2_2222;
        @(posedge clk);

        // Beat 3 (last)
        s_axi_wdata  <= 32'hA3A3_3333;
        s_axi_wlast  <= 1'b1;
        @(posedge clk);

        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        wait(s_axi_bvalid);
        @(posedge clk);
        s_axi_bready <= 1'b0;
        @(posedge clk);

        // Now Burst Read 4 words
        s_axi_araddr  <= 32'h0000_0200;
        s_axi_arlen   <= 8'd3;
        s_axi_arsize  <= 3'd2;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        wait(s_axi_arready);
        @(posedge clk);
        s_axi_arvalid <= 1'b0;

        // Beat 0
        @(negedge clk);
        wait(s_axi_rvalid);
        $display("  -> Read beat 0: data=0x%08x, last=%b", s_axi_rdata, s_axi_rlast);
        if (s_axi_rdata == 32'hA0A0_0000 && !s_axi_rlast) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        // Beat 1
        @(negedge clk);
        wait(s_axi_rvalid);
        $display("  -> Read beat 1: data=0x%08x, last=%b", s_axi_rdata, s_axi_rlast);
        if (s_axi_rdata == 32'hA1A1_1111 && !s_axi_rlast) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        // Beat 2
        @(negedge clk);
        wait(s_axi_rvalid);
        $display("  -> Read beat 2: data=0x%08x, last=%b", s_axi_rdata, s_axi_rlast);
        if (s_axi_rdata == 32'hA2A2_2222 && !s_axi_rlast) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        // Beat 3 (last)
        @(negedge clk);
        wait(s_axi_rvalid);
        $display("  -> Read beat 3: data=0x%08x, last=%b", s_axi_rdata, s_axi_rlast);
        if (s_axi_rdata == 32'hA3A3_3333 && s_axi_rlast) begin
            $display("  -> Burst read 4 beats with RLAST PASS!");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Burst read beat 3 FAIL!");
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        s_axi_rready <= 1'b0;

        $display("================================================================");
        $display(" Total PASS: %0d   Total FAIL: %0d", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(" *** ALL AXI RAM IP TESTS PASSED SUCCESSFULLY! ***\n");
        end else begin
            $display(" *** SOME AXI RAM TESTS FAILED! ***\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
