// =============================================================================
// File: tb_packet_counter.v
// Minimal directed self-checking testbench for:
//   packet_counter.v  +  packet_counter_axi4lite_wrapper.v
//
// Tests:
//   T1: Reset state — all counters 0, enable=0
//   T2: Enable via CONTROL register write (bit 0 = 1)
//   T3: Counter increments — one pulse each: rx, processed, crc_err, fifo_ovf
//   T4: Multiple pulses — 3 x packet_received
//   T5: Counter clear via CONTROL bit 1
//   T6: Disable (enable=0) — events must not increment counters
//   T7: AXI4-Lite invalid-address SLVERR check
// =============================================================================

`timescale 1ns / 1ps

module tb_packet_counter;

    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    reg aclk;
    reg aresetn;

    initial aclk = 0;
    always #5 aclk = ~aclk;   // 100 MHz

    // -------------------------------------------------------------------------
    // DUT Event Inputs
    // -------------------------------------------------------------------------
    reg packet_received;
    reg packet_processed;
    reg crc_error;
    reg fifo_overflow;

    // -------------------------------------------------------------------------
    // AXI4-Lite Interface
    // -------------------------------------------------------------------------
    reg  [31:0] s_axi_awaddr;
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
    reg         s_axi_arvalid;
    wire        s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    packet_counter_axi4lite_wrapper #(
        .ADDR_WIDTH    (32),
        .COUNTER_WIDTH (32)
    ) dut (
        .aclk              (aclk),
        .aresetn           (aresetn),
        .packet_received   (packet_received),
        .packet_processed  (packet_processed),
        .crc_error         (crc_error),
        .fifo_overflow     (fifo_overflow),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready)
    );

    // -------------------------------------------------------------------------
    // Tracking
    // -------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task check(input [31:0] actual, input [31:0] expected, input [63:0] tag);
        begin
            if (actual === expected) begin
                $display("  [PASS] %s: 0x%08X", tag, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s: got 0x%08X, expected 0x%08X", tag, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // AXI4-Lite Helpers
    // Independent AW and W — drive both simultaneously (simplest path).
    // -------------------------------------------------------------------------
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'b1111;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            // Wait until both channels accepted
            @(posedge aclk);
            while (!(s_axi_awready && s_axi_wready)) @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            // Wait for write response
            while (!s_axi_bvalid) @(posedge aclk);
            @(posedge aclk);
            s_axi_bready <= 1'b0;
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data, output [1:0] resp);
        begin
            @(posedge aclk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;
            @(posedge aclk);
            while (!s_axi_rvalid) @(posedge aclk);
            data = s_axi_rdata;
            resp = s_axi_rresp;
            s_axi_arvalid <= 1'b0;
            @(posedge aclk);
            s_axi_rready  <= 1'b0;
        end
    endtask

    // Register offsets (from wrapper source)
    localparam CTRL    = 32'h00;
    localparam STATUS  = 32'h04;
    localparam RX_CNT  = 32'h08;
    localparam PC_CNT  = 32'h0C;
    localparam CE_CNT  = 32'h10;
    localparam FO_CNT  = 32'h14;

    reg [31:0] rdata;
    reg [1:0]  rresp;

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Init
        pass_count = 0;
        fail_count = 0;
        aresetn          = 0;
        s_axi_awvalid    = 0;
        s_axi_wvalid     = 0;
        s_axi_bready     = 0;
        s_axi_arvalid    = 0;
        s_axi_rready     = 0;
        s_axi_awaddr     = 0;
        s_axi_wdata      = 0;
        s_axi_wstrb      = 4'b1111;
        s_axi_araddr     = 0;
        packet_received  = 0;
        packet_processed = 0;
        crc_error        = 0;
        fifo_overflow    = 0;

        $display("\n============================================================");
        $display("  Packet Counter + AXI4-Lite Wrapper — Directed Testbench");
        $display("============================================================\n");

        // Apply reset
        #30;
        aresetn = 1;
        #20;

        // ----------------------------------------------------------------
        // T1: Reset state
        // ----------------------------------------------------------------
        $display("--- T1: Reset state ---");
        axi_read(CTRL,   rdata, rresp); check(rdata, 32'h0, "CTRL default=0 (disabled)");
        axi_read(STATUS, rdata, rresp); check(rdata, 32'h0, "STATUS all 0 after reset");
        axi_read(RX_CNT, rdata, rresp); check(rdata, 32'h0, "RX_COUNT = 0");
        axi_read(PC_CNT, rdata, rresp); check(rdata, 32'h0, "PROC_COUNT = 0");
        axi_read(CE_CNT, rdata, rresp); check(rdata, 32'h0, "CRC_ERR_COUNT = 0");
        axi_read(FO_CNT, rdata, rresp); check(rdata, 32'h0, "FIFO_OVF_COUNT = 0");

        // ----------------------------------------------------------------
        // T2: Enable via CONTROL register
        // ----------------------------------------------------------------
        $display("\n--- T2: Enable counter via CONTROL bit 0 ---");
        axi_write(CTRL, 32'h1); // enable = 1
        axi_read(CTRL,   rdata, rresp); check(rdata, 32'h1, "CTRL enable=1 readback");
        axi_read(STATUS, rdata, rresp); check(rdata[0], 1'b1, "STATUS bit 0 (enabled) = 1");

        // ----------------------------------------------------------------
        // T3: Single event pulses
        // ----------------------------------------------------------------
        $display("\n--- T3: Single event increments ---");
        @(posedge aclk); packet_received  = 1; @(posedge aclk); packet_received  = 0;
        @(posedge aclk); packet_processed = 1; @(posedge aclk); packet_processed = 0;
        @(posedge aclk); crc_error        = 1; @(posedge aclk); crc_error        = 0;
        @(posedge aclk); fifo_overflow    = 1; @(posedge aclk); fifo_overflow    = 0;
        repeat(2) @(posedge aclk);

        axi_read(RX_CNT, rdata, rresp); check(rdata, 32'd1, "RX_COUNT = 1");
        axi_read(PC_CNT, rdata, rresp); check(rdata, 32'd1, "PROC_COUNT = 1");
        axi_read(CE_CNT, rdata, rresp); check(rdata, 32'd1, "CRC_ERR_COUNT = 1");
        axi_read(FO_CNT, rdata, rresp); check(rdata, 32'd1, "FIFO_OVF_COUNT = 1");

        // STATUS: bit 1 = any nonzero
        axi_read(STATUS, rdata, rresp); check(rdata[1], 1'b1, "STATUS bit 1 (any nonzero) = 1");

        // ----------------------------------------------------------------
        // T4: Multiple pulses on packet_received
        // ----------------------------------------------------------------
        $display("\n--- T4: Multiple RX pulses (3 more) ---");
        repeat(3) begin
            @(posedge aclk); packet_received = 1;
            @(posedge aclk); packet_received = 0;
        end
        repeat(2) @(posedge aclk);
        axi_read(RX_CNT, rdata, rresp); check(rdata, 32'd4, "RX_COUNT = 4 after 3 more");

        // ----------------------------------------------------------------
        // T5: Clear via CONTROL bit 1
        // ----------------------------------------------------------------
        $display("\n--- T5: Clear all counters via CONTROL bit 1 ---");
        axi_write(CTRL, 32'h3); // enable=1, clear=1
        repeat(2) @(posedge aclk);
        axi_write(CTRL, 32'h1); // restore enable=1 only

        axi_read(RX_CNT, rdata, rresp); check(rdata, 32'd0, "RX_COUNT cleared = 0");
        axi_read(PC_CNT, rdata, rresp); check(rdata, 32'd0, "PROC_COUNT cleared = 0");
        axi_read(CE_CNT, rdata, rresp); check(rdata, 32'd0, "CRC_ERR_COUNT cleared = 0");
        axi_read(FO_CNT, rdata, rresp); check(rdata, 32'd0, "FIFO_OVF_COUNT cleared = 0");

        // ----------------------------------------------------------------
        // T6: Disable (enable=0) — events must not increment
        // ----------------------------------------------------------------
        $display("\n--- T6: Events while disabled (enable=0) ---");
        axi_write(CTRL, 32'h0); // disable
        @(posedge aclk); packet_received = 1; @(posedge aclk); packet_received = 0;
        @(posedge aclk); crc_error = 1;       @(posedge aclk); crc_error = 0;
        repeat(2) @(posedge aclk);
        axi_read(RX_CNT, rdata, rresp); check(rdata, 32'd0, "RX_COUNT stays 0 when disabled");
        axi_read(CE_CNT, rdata, rresp); check(rdata, 32'd0, "CRC_ERR stays 0 when disabled");

        // ----------------------------------------------------------------
        // T7: Invalid address returns SLVERR
        // ----------------------------------------------------------------
        $display("\n--- T7: Invalid address SLVERR ---");
        axi_read(32'h18, rdata, rresp);  // unmapped offset
        check({30'b0, rresp}, {30'b0, 2'b10}, "Read unmapped 0x18 -> SLVERR");
        axi_write(32'h08, 32'hDEAD);    // write to read-only RX_COUNT
        // After the write, bresp should be SLVERR (2'b10)
        axi_read(STATUS, rdata, rresp);
        // Can't directly check bresp from axi_write task, check counter unchanged
        axi_read(RX_CNT, rdata, rresp); check(rdata, 32'd0, "RX_COUNT unchanged after SLVERR write");

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("\n============================================================");
        $display("  Total PASS: %0d   Total FAIL: %0d", pass_count, fail_count);
        $display("============================================================\n");

        if (fail_count == 0)
            $display(">>> ALL PACKET COUNTER TESTS PASSED <<<\n");
        else
            $display(">>> SOME TESTS FAILED <<<\n");

        $finish;
    end

endmodule
