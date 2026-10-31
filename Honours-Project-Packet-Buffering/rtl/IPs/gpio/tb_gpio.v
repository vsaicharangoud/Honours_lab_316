/*
 * ============================================================================
 * File: tb_gpio.v
 * Project: Reliable Data Transport System SoC
 * Description: Self-checking Testbench for GPIO IP Core (AXI4 & Core)
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

`include "gpio_defines.vh"

module tb_gpio;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter ID_WIDTH   = 8;
    parameter STRB_WIDTH = 4;
    parameter USER_WIDTH = 1;
    parameter GPIO_WIDTH = 32;

    reg clk;
    reg rst;
    reg rst_n;

    // AXI4 Master Test Signals
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

    // Physical GPIO signals
    reg  [GPIO_WIDTH-1:0] gpio_in;
    wire [GPIO_WIDTH-1:0] gpio_out;
    wire [GPIO_WIDTH-1:0] gpio_oe;
    wire                  gpio_irq;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    gpio_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .STRB_WIDTH (STRB_WIDTH),
        .USER_WIDTH (USER_WIDTH),
        .GPIO_WIDTH (GPIO_WIDTH)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .rst_n          (rst_n),
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
        .s_axi_rready   (s_axi_rready),
        .gpio_i         (gpio_in),
        .gpio_o         (gpio_out),
        .gpio_oe        (gpio_oe),
        .gpio_irq_o     (gpio_irq)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // AXI Write Task
    task axi_write(input [31:0] addr, input [31:0] data);
    begin
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 4'hF;
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

    // AXI Read Task
    task axi_read(input [31:0] addr, output [31:0] data, output [1:0] resp);
    begin
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        wait(s_axi_arready);
        @(posedge clk);
        s_axi_arvalid <= 1'b0;

        wait(s_axi_rvalid);
        data = s_axi_rdata;
        resp = s_axi_rresp;
        @(posedge clk);
        s_axi_rready  <= 1'b0;
        @(posedge clk);
    end
    endtask

    reg [31:0] rdata;
    reg [1:0]  rresp;

    initial begin
        rst           = 1'b1;
        rst_n         = 1'b0;
        gpio_in       = 32'd0;
        s_axi_awid    = 8'd1;
        s_axi_awaddr  = 32'd0;
        s_axi_awlen   = 8'd0;
        s_axi_awsize  = 3'd2;
        s_axi_awburst = 2'd0;
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
        s_axi_arburst = 2'd0;
        s_axi_arlock  = 1'b0;
        s_axi_arcache = 4'd0;
        s_axi_arprot  = 3'd0;
        s_axi_arqos   = 4'd0;
        s_axi_arregion= 4'd0;
        s_axi_aruser  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        $display("================================================================");
        $display(" Starting GPIO IP AXI4 Verification Testbench ");
        $display(" Base Address: 0x0002_2000");
        $display("================================================================");

        #40;
        @(posedge clk);
        rst   = 1'b0;
        rst_n = 1'b1;
        #20;

        // TEST 1: Check Reset Values
        $display("[TEST 1] Verifying initial reset values...");
        axi_read(32'h0002_2004, rdata, rresp); // DATA_OUT
        if (rdata == 32'd0 && gpio_out == 32'd0) begin
            $display("  -> DATA_OUT reset value PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> DATA_OUT reset value FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        axi_read(32'h0002_2008, rdata, rresp); // DIR
        if (rdata == 32'd0 && gpio_oe == 32'd0) begin
            $display("  -> DIR reset value PASS (all inputs): 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> DIR reset value FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 2: Direction Register Configuration
        $display("[TEST 2] Testing Direction (DIR) register configuration...");
        axi_write(32'h0002_2008, 32'h0000_000F); // Configure pins [3:0] as outputs
        axi_read(32'h0002_2008, rdata, rresp);
        if (rdata == 32'h0000_000F && gpio_oe == 32'h0000_000F) begin
            $display("  -> DIR register write/read PASS: 0x%08x, gpio_oe: 0x%08x", rdata, gpio_oe);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> DIR register write/read FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 3: Output Data Register & Pins
        $display("[TEST 3] Testing DATA_OUT register and pin driving...");
        axi_write(32'h0002_2004, 32'h0000_000A); // Write 0b1010 to outputs
        #10;
        axi_read(32'h0002_2004, rdata, rresp);
        if (rdata == 32'h0000_000A && gpio_out == 32'h0000_000A) begin
            $display("  -> DATA_OUT write/read PASS: 0x%08x, gpio_out: 0x%08x", rdata, gpio_out);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> DATA_OUT write/read FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 4: Atomic Set and Clear Operations
        $display("[TEST 4] Testing Atomic SET and CLEAR operations...");
        axi_write(32'h0002_200C, 32'h0000_0001); // Set bit 0 (0b1010 -> 0b1011)
        #10;
        axi_read(32'h0002_2004, rdata, rresp);
        if (rdata == 32'h0000_000B && gpio_out == 32'h0000_000B) begin
            $display("  -> Atomic SET PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Atomic SET FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        axi_write(32'h0002_2010, 32'h0000_0002); // Clear bit 1 (0b1011 -> 0b1001)
        #10;
        axi_read(32'h0002_2004, rdata, rresp);
        if (rdata == 32'h0000_0009 && gpio_out == 32'h0000_0009) begin
            $display("  -> Atomic CLEAR PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Atomic CLEAR FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 5: External Input Synchronizer & Readback
        $display("[TEST 5] Testing external GPIO inputs reading via DATA_IN...");
        gpio_in = 32'hCAFE_BABE;
        #30; // Wait 3 clocks for 2-stage synchronizer
        axi_read(32'h0002_2000, rdata, rresp);
        if (rdata == 32'hCAFE_BABE) begin
            $display("  -> DATA_IN synchronized read PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> DATA_IN synchronized read FAIL: 0x%08x (expected 0xCAFEBABE)", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 6: Interrupt Generation and W1C Clearing
        $display("[TEST 6] Testing pin edge interrupt generation and W1C clear...");
        // Enable interrupt on bit 8, edge-triggered (type=0), rising-edge (pol=0)
        axi_write(32'h0002_2014, 32'h0000_0100); // INT_EN bit 8
        axi_write(32'h0002_2018, 32'h0000_0000); // INT_TYPE = edge
        axi_write(32'h0002_201C, 32'h0000_0000); // INT_POL = rising

        // Transition bit 8 from 0 -> 1 on gpio_in
        gpio_in[8] = 1'b0;
        #30;
        gpio_in[8] = 1'b1;
        #40; // Allow synchronizer and edge detector to assert

        if (gpio_irq == 1'b1) begin
            $display("  -> gpio_irq_o asserted PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> gpio_irq_o asserted FAIL");
            fail_count = fail_count + 1;
        end

        // Check INT_STATUS register
        axi_read(32'h0002_2020, rdata, rresp);
        if (rdata[8] == 1'b1) begin
            $display("  -> INT_STATUS pending bit 8 PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> INT_STATUS pending bit 8 FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // Clear interrupt via W1C
        axi_write(32'h0002_2020, 32'h0000_0100);
        #20;
        axi_read(32'h0002_2020, rdata, rresp);
        if (rdata[8] == 1'b0 && gpio_irq == 1'b0) begin
            $display("  -> W1C interrupt clear and IRQ deassertion PASS: STATUS=0x%08x, IRQ=%b", rdata, gpio_irq);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> W1C interrupt clear FAIL: STATUS=0x%08x, IRQ=%b", rdata, gpio_irq);
            fail_count = fail_count + 1;
        end

        // TEST 7: Invalid Address Access
        $display("[TEST 7] Testing unmapped register access error response...");
        axi_read(32'h0002_20F0, rdata, rresp);
        if (rresp == 2'b10) begin
            $display("  -> Unmapped read returned SLVERR PASS (resp = 2'b10)");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Unmapped read failed to return SLVERR (resp = %b)", rresp);
            fail_count = fail_count + 1;
        end

        $display("================================================================");
        $display(" Total PASS: %0d   Total FAIL: %0d", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(" *** ALL GPIO IP TESTS PASSED SUCCESSFULLY! ***\n");
        end else begin
            $display(" *** SOME GPIO IP TESTS FAILED! ***\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
