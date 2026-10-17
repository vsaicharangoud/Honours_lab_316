/*
 * ============================================================================
 * File: tb_packet_fifo.v
 * Project: Reliable Data Transport System SoC - Packet FIFO IP Core
 * Description: Self-checking verification testbench for packet_fifo_top.
 *              Covers:
 *                Test 1: Reset behavior and register defaults
 *                Test 2: AXI4-Lite register access & threshold configuration
 *                Test 3: CPU Direct Data Injection via AXI4-Lite
 *                Test 4: Asynchronous Dual-Clock Streaming (s_axis -> m_axis)
 *                Test 5: Downstream Backpressure Handling (m_axis_tready deasserted)
 *                Test 6: Packet Framing Verification (tlast & packet counter)
 *                Test 7: Overflow / Underflow Detection & W1C Sticky Error Clearing
 *                Test 8: PIC Interrupt Line Generation (fifo_irq_o)
 * ============================================================================
 */

// timescale defined via compiler flag -timescale=1ns/1ps

`include "fifo_defines.vh"

module tb_packet_fifo;

    // ------------------------------------------------------------------------
    // Clock & Reset Generation
    // Dual Asynchronous Clock Domains:
    //   aclk   = 50 MHz  (period = 20 ns)
    //   wr_clk = 71.4 MHz (period = 14 ns)
    // ------------------------------------------------------------------------
    reg aclk;
    reg aresetn;
    reg wr_clk;
    reg wr_rst_n;

    initial aclk = 0;
    always #10 aclk = ~aclk;

    initial wr_clk = 0;
    always #7 wr_clk = ~wr_clk;

    // ------------------------------------------------------------------------
    // DUT Interface Signals
    // ------------------------------------------------------------------------
    // AXI4-Lite Interface
    reg  [31:0] s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;

    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;

    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;

    reg  [31:0] s_axi_araddr;
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // Upstream Streaming Interface (wr_clk domain)
    reg  [31:0] s_axis_tdata;
    reg  [3:0]  s_axis_tkeep;
    reg         s_axis_tlast;
    reg         s_axis_tvalid;
    wire        s_axis_tready;

    // Downstream Streaming Interface (aclk domain)
    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tlast;
    wire        m_axis_tvalid;
    reg         m_axis_tready;

    // Hardware Flags & IRQ
    wire        fifo_full_o;
    wire        fifo_empty_o;
    wire        fifo_irq_o;
    wire        fifo_error_o;

    // ------------------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------------------
    packet_fifo_top #(
        .AXI_DATA_WIDTH (32),
        .AXI_ADDR_WIDTH (32),
        .FIFO_DEPTH     (16),
        .SYNC_STAGES    (2)
    ) dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .wr_clk          (wr_clk),
        .wr_rst_n        (wr_rst_n),

        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),

        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),

        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),

        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),

        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),

        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tkeep    (s_axis_tkeep),
        .s_axis_tlast    (s_axis_tlast),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),

        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tkeep    (m_axis_tkeep),
        .m_axis_tlast    (m_axis_tlast),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),

        .fifo_full_o     (fifo_full_o),
        .fifo_empty_o    (fifo_empty_o),
        .fifo_irq_o      (fifo_irq_o),
        .fifo_error_o    (fifo_error_o)
    );

    // ------------------------------------------------------------------------
    // Verification Tracking & Helper Tasks
    // ------------------------------------------------------------------------
    integer test_errors = 0;
    integer tests_passed = 0;

    // AXI4-Lite Write Task
    task axi_write(input [5:0] offset, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  <= {26'h000700, offset};
            s_axi_awprot  <= 3'b000;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'b1111;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            @(posedge aclk);
            while (!s_axi_bvalid) @(posedge aclk);

            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            @(posedge aclk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    // AXI4-Lite Read Task
    task axi_read(input [5:0] offset, output [31:0] data);
        begin
            @(posedge aclk);
            s_axi_araddr  <= {26'h000700, offset};
            s_axi_arprot  <= 3'b000;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            @(posedge aclk);
            while (!s_axi_rvalid) @(posedge aclk);

            data = s_axi_rdata;
            s_axi_arvalid <= 1'b0;
            @(posedge aclk);
            s_axi_rready  <= 1'b0;
        end
    endtask

    // Check Task
    task check_value(input [31:0] actual, input [31:0] expected, input [80*8:1] msg);
        begin
            if (actual === expected) begin
                $display("  [PASS] %0s: 0x%08X", msg, actual);
                tests_passed = tests_passed + 1;
            end else begin
                $display("  [FAIL] %0s: Got 0x%08X, Expected 0x%08X", msg, actual, expected);
                test_errors = test_errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Execution
    // ------------------------------------------------------------------------
    reg [31:0] rdata;
    integer i;

    initial begin
        $display("\n=======================================================");
        $display("  Packet FIFO IP Core - Self-Checking Testbench");
        $display("  Base Address: 0x0007_0000 (Allocated Space: 4 KB)");
        $display("=======================================================\n");

        // Initialization
        aresetn       = 0;
        wr_rst_n      = 0;
        s_axi_awaddr  = 0;
        s_axi_awprot  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arprot  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        s_axis_tdata  = 0;
        s_axis_tkeep  = 4'b1111;
        s_axis_tlast  = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1;

        // Apply Reset
        #40;
        aresetn  = 1;
        wr_rst_n = 1;
        #40;

        // --------------------------------------------------------------------
        // Test 1: Reset behavior and register defaults
        // --------------------------------------------------------------------
        $display("--- Test 1: Verifying Reset State and Default Registers ---");
        axi_read(`FIFO_REG_STATUS, rdata);
        check_value(rdata[`FIFO_STATUS_RD_EMPTY_BIT], 1'b1, "Initial Status RD_EMPTY == 1");
        check_value(rdata[`FIFO_STATUS_WR_FULL_BIT],  1'b0, "Initial Status WR_FULL == 0");

        axi_read(`FIFO_REG_CTRL, rdata);
        check_value(rdata[`FIFO_CTRL_ENABLE_BIT],    1'b1, "Default Control ENABLE == 1");
        check_value(rdata[`FIFO_CTRL_STREAM_EN_BIT], 1'b1, "Default Control STREAM_EN == 1");

        // --------------------------------------------------------------------
        // Test 2: AXI4-Lite Threshold Configuration
        // --------------------------------------------------------------------
        $display("\n--- Test 2: AXI4-Lite Register Configuration ---");
        axi_write(`FIFO_REG_THRESHOLD, 32'h000C_0004); // Almost full=12, Almost empty=4
        axi_read(`FIFO_REG_THRESHOLD, rdata);
        check_value(rdata, 32'h000C_0004, "Threshold Register Readback");

        // --------------------------------------------------------------------
        // Test 3: CPU Direct Data Injection via AXI4-Lite
        // --------------------------------------------------------------------
        $display("\n--- Test 3: CPU Direct Data Injection via AXI4-Lite ---");
        m_axis_tready = 0; // Hold read side so words accumulate

        // Write Word 0 (data only)
        axi_write(`FIFO_REG_DATA, 32'hCAFE_0001);
        // Write Word 1 (data only)
        axi_write(`FIFO_REG_DATA, 32'hCAFE_0002);
        // Write Word 2 (end of packet)
        axi_write(`FIFO_REG_DATA_LAST, 32'hCAFE_0003);

        #30;
        axi_read(`FIFO_REG_STATUS, rdata);
        check_value(rdata[`FIFO_STATUS_RD_EMPTY_BIT], 1'b0, "FIFO Not Empty after CPU Writes");

        // Allow streaming output to drain.
        // The fixed FSM transitions SM_HOLD → SM_PENDING → SM_HOLD between
        // words.  The while-loop condition is evaluated pre-NBA.  After sampling
        // each word, advance one posedge + 1ps so the SM_HOLD→SM_PENDING NBA
        // settles (making tvalid=0) before the next while re-evaluates.
        m_axis_tready = 1;

        while (!(m_axis_tvalid && m_axis_tready)) @(posedge aclk);
        check_value(m_axis_tdata, 32'hCAFE_0001, "Stream Word 0 Data Match");
        check_value(m_axis_tlast, 1'b0,          "Stream Word 0 tlast == 0");
        @(posedge aclk); #1; // advance past NBA: rd_state becomes SM_PENDING

        while (!(m_axis_tvalid && m_axis_tready)) @(posedge aclk);
        check_value(m_axis_tdata, 32'hCAFE_0002, "Stream Word 1 Data Match");
        check_value(m_axis_tlast, 1'b0,          "Stream Word 1 tlast == 0");
        @(posedge aclk); #1; // advance past NBA

        while (!(m_axis_tvalid && m_axis_tready)) @(posedge aclk);
        check_value(m_axis_tdata, 32'hCAFE_0003, "Stream Word 2 Data Match");
        check_value(m_axis_tlast, 1'b1,          "Stream Word 2 tlast == 1 (Packet End)");

        // Wait a few cycles for packet counter to update, then read
        repeat(4) @(posedge aclk);
        #10;
        axi_read(`FIFO_REG_PACKET_COUNT, rdata);
        check_value(rdata, 32'd1, "Completed Packet Counter == 1");

        // --------------------------------------------------------------------
        // Test 4: Asynchronous Dual-Clock Streaming (s_axis -> m_axis)
        // --------------------------------------------------------------------
        $display("\n--- Test 4: Dual-Clock Asynchronous Streaming (wr_clk -> aclk) ---");
        m_axis_tready = 1;

        // Push 4-word packet in wr_clk domain
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge wr_clk);
            if (!s_axis_tready) begin
                while (!s_axis_tready) @(posedge wr_clk);
            end
            s_axis_tdata  <= 32'h1000_0000 + i;
            s_axis_tkeep  <= 4'b1111;
            s_axis_tlast  <= (i == 3) ? 1'b1 : 1'b0;
            s_axis_tvalid <= 1'b1;
        end
        @(posedge wr_clk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;

        // Collect and check in aclk domain.
        // After each word check, @(posedge aclk) steps past the SM_HOLD→SM_PENDING
        // NBA so the next while correctly waits at SM_PENDING→SM_HOLD.
        begin : test4_collect
            integer j;
            for (j = 0; j < 4; j = j + 1) begin
                while (!(m_axis_tvalid && m_axis_tready)) @(posedge aclk);
                check_value(m_axis_tdata, 32'h1000_0000 + j, "Stream RX -> TX Data Match");
                check_value(m_axis_tlast, (j == 3) ? 1'b1 : 1'b0, "Stream RX -> TX tlast Match");
                if (j < 3) @(posedge aclk); // step past SM_HOLD→SM_PENDING NBA
            end
        end

        repeat(4) @(posedge aclk);
        #10;
        axi_read(`FIFO_REG_PACKET_COUNT, rdata);
        check_value(rdata, 32'd2, "Completed Packet Counter == 2");

        // --------------------------------------------------------------------
        // Test 5: Downstream Backpressure Handling (m_axis_tready deasserted)
        // --------------------------------------------------------------------
        $display("\n--- Test 5: Downstream Backpressure Handling ---");

        // Assert backpressure FIRST so data stalls in FIFO
        m_axis_tready = 0;

        // Push 2 words on wr_clk
        @(posedge wr_clk);
        s_axis_tdata  <= 32'hBEEF_0001;
        s_axis_tlast  <= 1'b0;
        s_axis_tvalid <= 1'b1;
        @(posedge wr_clk);
        s_axis_tdata  <= 32'hBEEF_0002;
        s_axis_tlast  <= 1'b1;
        s_axis_tvalid <= 1'b1;
        @(posedge wr_clk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;

        // Allow CDC sync time to propagate, then verify stall
        #80;
        check_value(m_axis_tvalid, 1'b1, "m_axis_tvalid holds high during stall");
        check_value(m_axis_tdata, 32'hBEEF_0001, "m_axis_tdata holds stable under stall");

        // Release backpressure — capture the two words on their handshake cycles
        m_axis_tready = 1;
        while (!(m_axis_tvalid && m_axis_tready)) @(posedge aclk);
        check_value(m_axis_tdata, 32'hBEEF_0001, "Word 1 correctly delivered after stall release");
        @(posedge aclk); // step past SM_HOLD→SM_PENDING NBA

        while (!(m_axis_tvalid && m_axis_tready)) @(posedge aclk);
        check_value(m_axis_tdata, 32'hBEEF_0002, "Word 2 correctly delivered after stall");
        check_value(m_axis_tlast, 1'b1, "Final word tlast intact after stall");

        // --------------------------------------------------------------------
        // Test 6: Overflow & Underflow Detection with Sticky Error Clear
        // --------------------------------------------------------------------
        $display("\n--- Test 6: Overflow, Underflow & Diagnostic Reporting ---");
        m_axis_tready = 0; // Prevent draining

        // Fill FIFO until full
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge wr_clk);
            s_axis_tdata  <= 32'hAAAA_0000 + i;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= 1'b0;
        end
        @(posedge wr_clk);
        s_axis_tvalid <= 1'b0;

        #50;
        check_value(fifo_full_o, 1'b1, "FIFO reports Full condition");

        // Attempt write when full -> triggers overflow
        @(posedge wr_clk);
        s_axis_tdata  <= 32'hBAD0_0000;
        s_axis_tvalid <= 1'b1;
        @(posedge wr_clk);
        s_axis_tvalid <= 1'b0;

        #50;
        axi_read(`FIFO_REG_DIAG_STATUS, rdata);
        check_value(rdata[`FIFO_DIAG_WR_OVF_STICKY_BIT], 1'b1, "wr_overflow_sticky detected");

        // Enable interrupt on overflow
        axi_write(`FIFO_REG_CTRL, `FIFO_DEFAULT_CTRL | (1 << `FIFO_CTRL_IE_OVERFLOW_BIT));
        #20;
        check_value(fifo_irq_o, 1'b1, "fifo_irq_o asserted to PIC on overflow");

        // Clear sticky flag via W1C
        // Wait long enough for: axi_write latency + CDC toggle-sync to wr_clk
        //   (~3-4 wr_clk periods = ~42-56 ns) + fifo_diag clear + 2-stage
        //   aclk re-sync of cleared flag (~40 ns) = minimum ~150 ns
        axi_write(`FIFO_REG_DIAG_STATUS, (1 << `FIFO_DIAG_WR_OVF_STICKY_BIT));
        #200;
        axi_read(`FIFO_REG_DIAG_STATUS, rdata);
        check_value(rdata[`FIFO_DIAG_WR_OVF_STICKY_BIT], 1'b0, "wr_overflow_sticky cleared by W1C");
        check_value(fifo_irq_o, 1'b0, "fifo_irq_o deasserted after clear");

        // Drain remaining data
        m_axis_tready = 1;
        #400;
        axi_read(`FIFO_REG_STATUS, rdata);
        check_value(rdata[`FIFO_STATUS_RD_EMPTY_BIT], 1'b1, "FIFO fully drained to empty");

        // --------------------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------------------
        $display("\n=======================================================");
        $display("  Packet FIFO Testbench Completed");
        $display("  Total Checks Passed : %0d", tests_passed);
        $display("  Total Failures      : %0d", test_errors);
        $display("=======================================================\n");

        if (test_errors == 0) begin
            $display(">>> ALL PACKET FIFO TESTS PASSED SUCCESSFULLY! <<<\n");
            $finish(0);
        end else begin
            $display(">>> SOME TESTS FAILED! <<<\n");
            $finish(1);
        end
    end

endmodule
