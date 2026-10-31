/*
 * ============================================================================
 * File: tb_timer.v
 * Project: Reliable Data Transport System SoC
 * Description: Self-checking Testbench for Timer IP (AXI4 & Core)
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

`include "timer_defines.vh"

module tb_timer;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter ID_WIDTH   = 8;
    parameter STRB_WIDTH = 4;
    parameter USER_WIDTH = 1;

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

    // Hardware signals
    wire timer_irq;
    wire timer_match;
    wire timer_pwm;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate DUT
    timer_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .STRB_WIDTH (STRB_WIDTH),
        .USER_WIDTH (USER_WIDTH)
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
        .timer_irq_o    (timer_irq),
        .timer_match_o  (timer_match),
        .timer_pwm_o    (timer_pwm)
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
        // Initialize signals
        rst           = 1'b1;
        rst_n         = 1'b0;
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
        $display(" Starting Timer IP AXI4 Verification Testbench ");
        $display(" Base Address: 0x0002_1000");
        $display("================================================================");

        #40;
        @(posedge clk);
        rst   = 1'b0;
        rst_n = 1'b1;
        #20;

        // TEST 1: Check Reset Values
        $display("[TEST 1] Verifying initial reset values...");
        axi_read(32'h0002_1004, rdata, rresp); // STATUS
        if (rdata == 32'd0 && rresp == 2'b00) begin
            $display("  -> STATUS reset value PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> STATUS reset value FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        axi_read(32'h0002_1008, rdata, rresp); // VALUE
        if (rdata == 32'd0 && rresp == 2'b00) begin
            $display("  -> VALUE reset value PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> VALUE reset value FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 2: Register Write & Readback
        $display("[TEST 2] Testing COMPARE and PRESCALER register configuration...");
        axi_write(32'h0002_100C, 32'd10);      // Set COMPARE = 10
        axi_read(32'h0002_100C, rdata, rresp);
        if (rdata == 32'd10) begin
            $display("  -> COMPARE register write/read PASS: %d", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> COMPARE register write/read FAIL: %d", rdata);
            fail_count = fail_count + 1;
        end

        axi_write(32'h0002_1010, 32'd1);       // Set PRESCALER = 1 (div by 2)
        axi_read(32'h0002_1010, rdata, rresp);
        if (rdata == 32'd1) begin
            $display("  -> PRESCALER register write/read PASS: %d", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> PRESCALER register write/read FAIL: %d", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 3: One-shot Timer Operation with Interrupt
        $display("[TEST 3] Testing One-Shot mode with Compare Match and Interrupt...");
        // Reset prescaler to 0 (tick every clock), COMPARE = 8, One-shot (reload=0), IE=1, EN=1
        axi_write(32'h0002_1010, 32'd0); // prescaler = 0
        axi_write(32'h0002_100C, 32'd8); // compare = 8
        // CTRL: bit0=EN, bit1=RELOAD(0), bit2=RST(0), bit3=IE(1) => 4'b1001 = 0x9
        axi_write(32'h0002_1000, 32'h0000_0009);

        // Wait for 15 clock cycles for timer to count up to 8 and match
        #150;

        // Check if timer_irq is asserted
        if (timer_irq == 1'b1) begin
            $display("  -> timer_irq_o asserted PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> timer_irq_o asserted FAIL");
            fail_count = fail_count + 1;
        end

        // Check status register: should have match bit (bit 1) set and running (bit 0) cleared in one-shot
        axi_read(32'h0002_1004, rdata, rresp);
        if (rdata[1] == 1'b1) begin
            $display("  -> STATUS match bit PASS: 0x%08x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> STATUS match bit FAIL: 0x%08x", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 4: W1C Clear of Match Status & Interrupt Deassertion
        $display("[TEST 4] Testing W1C status clear and interrupt deassertion...");
        axi_write(32'h0002_1004, 32'h0000_0002); // write 1 to match bit to clear
        #20;
        axi_read(32'h0002_1004, rdata, rresp);
        if (rdata[1] == 1'b0 && timer_irq == 1'b0) begin
            $display("  -> W1C status clear and IRQ deasserted PASS: STATUS=0x%08x, IRQ=%b", rdata, timer_irq);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> W1C status clear FAIL: STATUS=0x%08x, IRQ=%b", rdata, timer_irq);
            fail_count = fail_count + 1;
        end

        // TEST 5: Periodic Auto-Reload Mode
        $display("[TEST 5] Testing Periodic Auto-Reload Mode...");
        // COMPARE = 5, RELOAD = 1, IE = 0, EN = 1
        axi_write(32'h0002_100C, 32'd5);
        axi_write(32'h0002_1000, 32'h0000_0007); // Reset counter and configure periodic
        axi_write(32'h0002_1000, 32'h0000_0003); // Run periodic
        #120; // Let it run multiple periods
        axi_read(32'h0002_1008, rdata, rresp); // Read counter value
        if (rdata <= 32'd5 && rresp == 2'b00) begin
            $display("  -> Counter wrapping within [0, 5] PASS: current VALUE = %d", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Counter wrapping FAIL: current VALUE = %d", rdata);
            fail_count = fail_count + 1;
        end

        // TEST 6: Invalid address access returns SLVERR
        $display("[TEST 6] Testing unmapped register access error response...");
        axi_read(32'h0002_10FC, rdata, rresp);
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
            $display(" *** ALL TIMER IP TESTS PASSED SUCCESSFULLY! ***\n");
        end else begin
            $display(" *** SOME TIMER IP TESTS FAILED! ***\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
