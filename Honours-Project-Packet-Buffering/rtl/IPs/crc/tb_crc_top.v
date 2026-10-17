/*
 * ============================================================================
 * File: tb_crc_top.v
 * Project: Reliable Data Transport System SoC
 * Description: Comprehensive Self-Checking Testbench for the CRC-32 IP Core.
 *              Verifies:
 *                1. AXI4-Lite Register Read/Write Access at Base 0x000A_0000
 *                2. Standard IEEE 802.3 Checksum on "123456789" (0xCBF43926)
 *                3. Streaming Valid Packet Processing (CRC_PASS assertion)
 *                4. Streaming Corrupted Packet Processing (CRC_ERROR assertion)
 *                5. Statistics Counters (Pass Count, Error Count, Byte Count)
 *                6. Interrupt Generation & W1C Status Clearing
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps

`include "crc_defines.vh"

module tb_crc_top;

    // ------------------------------------------------------------------------
    // Clock and Reset Signals
    // ------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Signals
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // Streaming Interface Signals
    // ------------------------------------------------------------------------
    reg  [31:0] s_axis_tdata;
    reg  [3:0]  s_axis_tkeep;
    reg         s_axis_tlast;
    reg         s_axis_tvalid;
    wire        s_axis_tready;

    // ------------------------------------------------------------------------
    // Hardware Event Outputs
    // ------------------------------------------------------------------------
    wire        crc_pass_o;
    wire        crc_error_o;
    wire        crc_done_o;
    wire        crc_busy_o;
    wire        irq_o;

    // Testbench Variables
    integer     test_errors;
    reg  [31:0] read_val;

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    crc_top #(
        .AXI_DATA_WIDTH (32),
        .AXI_ADDR_WIDTH (32)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),

        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awprot  (s_axi_awprot),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),

        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),

        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),

        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arprot  (s_axi_arprot),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),

        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tkeep  (s_axis_tkeep),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),

        .crc_pass_o    (crc_pass_o),
        .crc_error_o   (crc_error_o),
        .crc_done_o    (crc_done_o),
        .crc_busy_o    (crc_busy_o),
        .irq_o         (irq_o)
    );

    // ------------------------------------------------------------------------
    // Clock Generation: 100 MHz (10 ns period)
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // AXI4-Lite Master Bus Tasks
    // ------------------------------------------------------------------------
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'b1111;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            // Wait for address & data handshake
            while (!(s_axi_awready && s_axi_wready)) @(posedge clk);

            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            // Wait for response
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            while (!s_axi_arready) @(posedge clk);

            @(posedge clk);
            s_axi_arvalid <= 1'b0;

            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------------
    // Streaming Packet Send Task
    // ------------------------------------------------------------------------
    task send_axis_word(input [31:0] data, input [3:0] keep, input last);
        begin
            @(posedge clk);
            s_axis_tdata  <= data;
            s_axis_tkeep  <= keep;
            s_axis_tlast  <= last;
            s_axis_tvalid <= 1'b1;

            while (!s_axis_tready) @(posedge clk);

            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Sequence
    // ------------------------------------------------------------------------
    initial begin
        $display("================================================================");
        $display(" Starting CRC-32 IP Core Verification Testbench");
        $display(" Base Address: 0x000A_0000");
        $display("================================================================");

        test_errors   = 0;
        rst_n         = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 32'd0;
        s_axis_tkeep  = 4'b0000;
        s_axis_tlast  = 1'b0;

        // Apply Reset
        #20;
        rst_n = 1'b1;
        #20;

        // --------------------------------------------------------------------
        // TEST 1: AXI4-Lite Register Defaults & Write/Read
        // --------------------------------------------------------------------
        $display("[TEST 1] Testing AXI4-Lite Register Read/Write Access...");
        axi_read(32'h000A_0010, read_val); // POLY
        if (read_val !== `CRC32_DEFAULT_POLY_REV) begin
            $display("ERROR: Poly mismatch! Expected: 0x%08X, Got: 0x%08X", `CRC32_DEFAULT_POLY_REV, read_val);
            test_errors = test_errors + 1;
        end else begin
            $display("  -> Poly default verified: 0x%08X", read_val);
        end

        // Write Expected CRC Register
        axi_write(32'h000A_000C, 32'hCBF43926);
        axi_read(32'h000A_000C, read_val);
        if (read_val !== 32'hCBF43926) begin
            $display("ERROR: Exp CRC reg write failed! Got: 0x%08X", read_val);
            test_errors = test_errors + 1;
        end else begin
            $display("  -> Exp CRC reg write/read verified: 0x%08X", read_val);
        end

        // --------------------------------------------------------------------
        // TEST 2: Valid Packet Streaming Test ("123456789" -> 0xCBF43926)
        // --------------------------------------------------------------------
        $display("\n[TEST 2] Testing Streaming Packet with VALID CRC (IEEE 802.3 Checksum)...");
        // String "123456789":
        // Word 0: '1', '2', '3', '4' = 0x34333231 (bytes 0x31, 0x32, 0x33, 0x34)
        // Word 1: '5', '6', '7', '8' = 0x38373635 (bytes 0x35, 0x36, 0x37, 0x38)
        // Word 2: '9', 0, 0, 0       = 0x00000039 (byte 0x39, tkeep = 4'b0001)

        // Ensure Expected CRC register holds 0xCBF43926
        axi_write(32'h000A_000C, 32'hCBF43926);

        // Stream packet
        send_axis_word(32'h34333231, 4'b1111, 1'b0);
        send_axis_word(32'h38373635, 4'b1111, 1'b0);
        send_axis_word(32'h00000039, 4'b0001, 1'b1); // Last word, 1 byte

        // Wait for check completion
        #30;

        // Verify Calculated CRC Register
        axi_read(32'h000A_0008, read_val);
        $display("  -> Calculated CRC: 0x%08X (Expected: 0xCBF43926)", read_val);
        if (read_val !== 32'hCBF43926) begin
            $display("ERROR: Calculated CRC mismatch! Expected: 0xCBF43926, Got: 0x%08X", read_val);
            test_errors = test_errors + 1;
        end

        // Verify Pass Count Register
        axi_read(32'h000A_0024, read_val);
        $display("  -> Pass Count: %0d", read_val);
        if (read_val !== 32'd1) begin
            $display("ERROR: Pass count should be 1, Got: %0d", read_val);
            test_errors = test_errors + 1;
        end

        // Verify Byte Count (9 bytes processed)
        axi_read(32'h000A_0018, read_val);
        $display("  -> Processed Byte Count: %0d (Expected: 9)", read_val);
        if (read_val !== 32'd9) begin
            $display("ERROR: Byte count should be 9, Got: %0d", read_val);
            test_errors = test_errors + 1;
        end

        // --------------------------------------------------------------------
        // TEST 3: Corrupted Packet Streaming Test (CRC_ERROR)
        // --------------------------------------------------------------------
        $display("\n[TEST 3] Testing Streaming Packet with CORRUPTED Data...");
        // Send corrupted payload: "12345678A" (instead of "123456789")
        send_axis_word(32'h34333231, 4'b1111, 1'b0);
        send_axis_word(32'h38373635, 4'b1111, 1'b0);
        send_axis_word(32'h00000041, 4'b0001, 1'b1); // 'A' instead of '9'

        #30;

        // Verify Error Count Register
        axi_read(32'h000A_0020, read_val);
        $display("  -> Error Count: %0d", read_val);
        if (read_val !== 32'd1) begin
            $display("ERROR: Error count should be 1, Got: %0d", read_val);
            test_errors = test_errors + 1;
        end

        // Check Status Register
        axi_read(32'h000A_0004, read_val);
        $display("  -> Status Register: 0x%08X (Error bit = %b)", read_val, read_val[`CRC_STATUS_ERROR_BIT]);
        if (read_val[`CRC_STATUS_ERROR_BIT] !== 1'b1) begin
            $display("ERROR: Status error bit should be 1!");
            test_errors = test_errors + 1;
        end

        // --------------------------------------------------------------------
        // TEST 4: Interrupt Generation & Status Clear (W1C)
        // --------------------------------------------------------------------
        $display("\n[TEST 4] Testing Interrupt Enable and W1C Clearing...");
        // Enable Error Interrupt in Control Register (bit 3)
        axi_write(32'h000A_0000, 32'h0000001D); // Enable, AutoClear, IE_Done, IE_Error

        #10;
        if (irq_o !== 1'b1) begin
            $display("ERROR: IRQ output should be active!");
            test_errors = test_errors + 1;
        end else begin
            $display("  -> IRQ asserted successfully.");
        end

        // Clear Status Register Error bit (Write 1 to bit 3 of status register)
        axi_write(32'h000A_0004, (1 << `CRC_STATUS_ERROR_BIT) | (1 << `CRC_STATUS_DONE_BIT));
        #10;
        if (irq_o !== 1'b0) begin
            $display("ERROR: IRQ should clear after W1C!");
            test_errors = test_errors + 1;
        end else begin
            $display("  -> IRQ cleared successfully via W1C.");
        end

        // --------------------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------------------
        $display("\n================================================================");
        if (test_errors == 0) begin
            $display(" *** ALL TESTS PASSED SUCCESSFULLY! CRC-32 IP IS VERIFIED. *** ");
        end else begin
            $display(" *** TESTS FAILED! Total errors: %0d ***", test_errors);
        end
        $display("================================================================\n");

        #50;
        $finish;
    end

endmodule

`resetall
