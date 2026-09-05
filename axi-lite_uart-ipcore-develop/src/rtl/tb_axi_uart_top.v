`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// AXI-Lite UART testbench
// DUT:
//   axi_uart_top
//
// Register addresses are byte addresses:
//   0x00 : THR (write) / RBR (read)
//   0x04 : IER
//   0x08 : BAUD_DIVISOR (write when LCR[7]=1)
//   0x0C : LCR
//   0x14 : LSR
//
// The testbench uses a small baud divisor (4) so simulation finishes quickly.
// LCR = 0x03 => 8 data bits, no parity, 1 stop bit.
// -----------------------------------------------------------------------------

module tb_axi_uart_top;

  localparam integer AXI_DATA_WIDTH = 32;
  localparam integer AXI_ADDR_WIDTH = 5;
  localparam integer AXI_ID_WIDTH   = 12;
  localparam integer AXI_RESP_WIDTH = 2;
  localparam integer AXI_BYTE_NUM   = 4;

  localparam [AXI_ADDR_WIDTH-1:0] ADDR_THR = 5'h00;
  localparam [AXI_ADDR_WIDTH-1:0] ADDR_RBR = 5'h00;
  localparam [AXI_ADDR_WIDTH-1:0] ADDR_IER = 5'h04;
  localparam [AXI_ADDR_WIDTH-1:0] ADDR_BAUD = 5'h08;
  localparam [AXI_ADDR_WIDTH-1:0] ADDR_LCR = 5'h0C;
  localparam [AXI_ADDR_WIDTH-1:0] ADDR_LSR = 5'h14;

  localparam [AXI_DATA_WIDTH-1:0] LCR_8N1  = 32'h0000_0003;
  localparam [AXI_DATA_WIDTH-1:0] LCR_DLAB = 32'h0000_0083;
  localparam [AXI_DATA_WIDTH-1:0] TEST_BAUD_DIV = 32'd4;

  // ---------------------------------------------------------------------------
  // Clocks and reset
  // ---------------------------------------------------------------------------
  reg fixed_clk_i;
  reg axi_aclk_i;
  reg axi_aresetn_i;

  initial begin
    fixed_clk_i = 1'b0;
    forever #5 fixed_clk_i = ~fixed_clk_i;       // 100 MHz
  end

  initial begin
    axi_aclk_i = 1'b0;
    #2.5;
    forever #5 axi_aclk_i = ~axi_aclk_i;         // 100 MHz, phase shifted
  end

  // ---------------------------------------------------------------------------
  // AXI-Lite signals
  // ---------------------------------------------------------------------------
  reg  [AXI_ID_WIDTH-1:0]   axi_arid_i;
  reg  [AXI_ADDR_WIDTH-1:0] axi_araddr_i;
  reg                       axi_arvalid_i;
  wire                      axi_arready_o;

  wire [AXI_ID_WIDTH-1:0]   axi_rid_o;
  wire [AXI_DATA_WIDTH-1:0] axi_rdata_o;
  wire [AXI_RESP_WIDTH-1:0] axi_rresp_o;
  wire                      axi_rvalid_o;
  reg                       axi_rready_i;

  reg  [AXI_ID_WIDTH-1:0]   axi_awid_i;
  reg  [AXI_ADDR_WIDTH-1:0] axi_awaddr_i;
  reg                       axi_awvalid_i;

  wire                      axi_awready_o;

  reg  [AXI_DATA_WIDTH-1:0] axi_wdata_i;
  reg  [AXI_BYTE_NUM-1:0]   axi_wstrb_i;
  reg                       axi_wvalid_i;
  wire                      axi_wready_o;

  wire [AXI_ID_WIDTH-1:0]   axi_bid_o;
  wire [AXI_RESP_WIDTH-1:0] axi_bresp_o;
  wire                      axi_bvalid_o;
  reg                       axi_bready_i;

  reg                       uart_rx_i;
  reg                       loopback_en;
  wire                      uart_tx_o;
  wire                      read_interrupt_o;

  // Optional TX->RX loopback. It is enabled only for the loopback test so
  // the first TX-only test does not also fill the RX FIFO.
  always @(negedge fixed_clk_i) begin
    if (loopback_en)
      uart_rx_i <= uart_tx_o;
    else
      uart_rx_i <= 1'b1;
  end

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  axi_uart_top dut (
    .fixed_clk_i       (fixed_clk_i),
    .axi_aclk_i        (axi_aclk_i),
    .axi_aresetn_i     (axi_aresetn_i),

    .axi_arid_i        (axi_arid_i),
    .axi_araddr_i      (axi_araddr_i),
    .axi_arvalid_i     (axi_arvalid_i),
    .axi_arready_o     (axi_arready_o),

    .axi_rid_o         (axi_rid_o),
    .axi_rdata_o       (axi_rdata_o),
    .axi_rresp_o       (axi_rresp_o),
    .axi_rvalid_o      (axi_rvalid_o),
    .axi_rready_i      (axi_rready_i),

    .axi_awid_i        (axi_awid_i),
    .axi_awaddr_i      (axi_awaddr_i),
    .axi_awvalid_i     (axi_awvalid_i),
    .axi_awready_o     (axi_awready_o),

    .axi_wdata_i       (axi_wdata_i),
    .axi_wstrb_i       (axi_wstrb_i),
    .axi_wvalid_i      (axi_wvalid_i),
    .axi_wready_o      (axi_wready_o),

    .axi_bid_o         (axi_bid_o),
    .axi_bresp_o       (axi_bresp_o),
    .axi_bvalid_o      (axi_bvalid_o),
    .axi_bready_i      (axi_bready_i),

    .read_interrupt_o  (read_interrupt_o),

    .uart_rx_i         (uart_rx_i),
    .uart_tx_o         (uart_tx_o)
  );

  // ---------------------------------------------------------------------------
  // Waveforms
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("axi_uart.vcd");
    $dumpvars(0, tb_axi_uart_top);

`ifdef FSDB_DUMP
    $fsdbDumpfile("axi_uart.fsdb");
    $fsdbDumpvars(0, tb_axi_uart_top);
`endif
  end

  // ---------------------------------------------------------------------------
  // AXI write task
  //
  // This DUT expects AWVALID and WVALID together.
  // ---------------------------------------------------------------------------
  task automatic axi_write;
    input [AXI_ADDR_WIDTH-1:0] addr;
    input [AXI_DATA_WIDTH-1:0] data;
    input [AXI_ID_WIDTH-1:0] id;
    begin
      @(negedge axi_aclk_i);
      axi_awid_i    <= id;
      axi_awaddr_i  <= addr;
      axi_awvalid_i <= 1'b1;

      axi_wdata_i   <= data;
      axi_wstrb_i   <= 4'b1111;
      axi_wvalid_i  <= 1'b1;

      // This RTL gates BVALID with AWVALID&WVALID, so keep both valid
      // signals asserted until the write response is visible.
      while (!(axi_awready_o && axi_wready_o))
        @(posedge axi_aclk_i);

      axi_bready_i <= 1'b1;
      while (!axi_bvalid_o)
        @(posedge fixed_clk_i);

      if (axi_bresp_o !== 2'b00)
        $display("[%0t] ERROR: AXI WRITE response = %b", $time, axi_bresp_o);

      @(negedge axi_aclk_i);
      axi_awvalid_i <= 1'b0;
      axi_wvalid_i  <= 1'b0;
      axi_bready_i  <= 1'b0;

      $display("[%0t] AXI WRITE  addr=0x%02h data=0x%08h",
               $time, addr, data);
    end
  endtask

  // ---------------------------------------------------------------------------
  // AXI read task
  // ---------------------------------------------------------------------------
  task automatic axi_read;
    input  [AXI_ADDR_WIDTH-1:0] addr;
    input  [AXI_ID_WIDTH-1:0] id;
    output [AXI_DATA_WIDTH-1:0] data;
    begin
      @(negedge axi_aclk_i);
      axi_arid_i    <= id;
      axi_araddr_i  <= addr;
      axi_arvalid_i <= 1'b1;

      // This RTL gates RVALID with ARVALID, so keep ARVALID asserted
      // until the read response is visible.
      while (!axi_arready_o)
        @(posedge axi_aclk_i);

      axi_rready_i <= 1'b1;
      while (!axi_rvalid_o)
        @(posedge fixed_clk_i);

      data = axi_rdata_o;

      if (axi_rresp_o !== 2'b00)
        $display("[%0t] ERROR: AXI READ response = %b", $time, axi_rresp_o);

      @(negedge axi_aclk_i);
      axi_arvalid_i <= 1'b0;
      axi_rready_i  <= 1'b0;

      $display("[%0t] AXI READ   addr=0x%02h data=0x%08h",
               $time, addr, data);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Wait for TX to return to idle.
  //
  // uart_tx_o is normally high in idle. We additionally wait for the expected
  // number of bit periods to make sure the complete frame has been emitted.
  // For baud divisor 4, the RTL holds each UART bit for approximately 5 clocks.
  // 10 bits for 8N1 => approximately 50 fixed-clock cycles.
  // ---------------------------------------------------------------------------
  task automatic wait_tx_done;
    integer i;
    begin
      for (i = 0; i < 80; i = i + 1)
        @(posedge fixed_clk_i);

      $display("[%0t] TX observation window complete", $time);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main test
  // ---------------------------------------------------------------------------
  reg [AXI_DATA_WIDTH-1:0] read_data;
  reg [7:0] tx_byte;
  reg [7:0] rx_byte;

  initial begin
    // Initial values
    axi_aresetn_i = 1'b0;

    axi_arid_i    = '0;
    axi_araddr_i  = '0;
    axi_arvalid_i = 1'b0;
    axi_rready_i  = 1'b0;

    axi_awid_i    = '0;
    axi_awaddr_i  = '0;
    axi_awvalid_i = 1'b0;

    axi_wdata_i   = '0;
    axi_wstrb_i   = 4'b0000;
    axi_wvalid_i  = 1'b0;

    axi_bready_i  = 1'b0;

    // UART idle state is logic 1.
    uart_rx_i     = 1'b1;
    loopback_en   = 1'b0;

    tx_byte       = 8'hA5;
    rx_byte       = 8'h3C;

    $display("");
    $display("==============================================================");
    $display("        AXI-Lite UART VCS TESTBENCH STARTING");
    $display("==============================================================");

    // Reset
    repeat (5) @(posedge fixed_clk_i);
    axi_aresetn_i = 1'b1;
    $display("[%0t] Reset released", $time);

    repeat (5) @(posedge fixed_clk_i);

    // -------------------------------------------------------------------------
    // TEST 1: Configure baud divisor
    // -------------------------------------------------------------------------
    // Set DLAB = 1 first.
    axi_write(ADDR_LCR, LCR_DLAB, 12'h001);

    // Use a small divisor to make the simulation fast.
    axi_write(ADDR_BAUD, TEST_BAUD_DIV, 12'h002);

    // Return to 8N1 with DLAB = 0.
    axi_write(ADDR_LCR, LCR_8N1, 12'h003);

    // Enable RX interrupt/data-ready indication.
    axi_write(ADDR_IER, 32'h0000_0001, 12'h004);

    $display("[%0t] UART configured: 8N1, baud divisor=%0d",
             $time, TEST_BAUD_DIV);

    // -------------------------------------------------------------------------
    // TEST 2: Read initial LSR
    // -------------------------------------------------------------------------
    axi_read(ADDR_LSR, 12'h010, read_data);

    if (read_data[5] !== 1'b1 || read_data[6] !== 1'b1) begin
      $display("[%0t] WARNING: Initial LSR unexpected: 0x%08h",
               $time, read_data);
    end
    else begin
      $display("[%0t] PASS: LSR initially indicates TX empty", $time);
    end

    // -------------------------------------------------------------------------
    // TEST 3: TX
    // -------------------------------------------------------------------------
    $display("");
    $display("--------------------------------------------------------------");
    $display("TEST 3: UART TRANSMIT byte 0x%02h", tx_byte);
    $display("--------------------------------------------------------------");

    axi_write(ADDR_THR, {24'h0, tx_byte}, 12'h020);

    // Give the TX FIFO/controller time to start transmission.
    repeat (5) @(posedge fixed_clk_i);

    if (uart_tx_o !== 1'b0)
      $display("[%0t] WARNING: TX did not appear in START bit when expected",
               $time);
    else
      $display("[%0t] PASS: uart_tx_o entered START bit", $time);

    wait_tx_done;

    if (uart_tx_o !== 1'b1)
      $display("[%0t] ERROR: TX line is not idle after transmission", $time);
    else
      $display("[%0t] PASS: TX returned to idle", $time);

    // -------------------------------------------------------------------------
    // TEST 4: RX using TX->RX loopback
    // -------------------------------------------------------------------------
    $display("");
    $display("--------------------------------------------------------------");
    $display("TEST 4: UART LOOPBACK");
    $display("         TX byte 0x%02h -> uart_tx_o -> uart_rx_i", tx_byte);
    $display("--------------------------------------------------------------");

    // Enable loopback BEFORE writing the byte so the receiver sees the
    // complete START bit and all following UART bits.
    loopback_en = 1'b1;
    repeat (2) @(posedge fixed_clk_i);

    axi_write(ADDR_THR, {24'h0, rx_byte}, 12'h030);

    wait_tx_done;

    // Allow the synchronized receiver to finish and push the byte to FIFO.
    repeat (20) @(posedge fixed_clk_i);
    loopback_en = 1'b0;
    uart_rx_i = 1'b1;

    // -------------------------------------------------------------------------
    // TEST 5: Check LSR data-ready
    // -------------------------------------------------------------------------
    axi_read(ADDR_LSR, 12'h040, read_data);

    if (read_data[0] !== 1'b1) begin
      $display("[%0t] ERROR: RX DATA_READY bit is not set. LSR=0x%08h",
               $time, read_data);
    end
    else begin
      $display("[%0t] PASS: RX DATA_READY asserted", $time);
    end

    // -------------------------------------------------------------------------
    // TEST 6: Read received byte
    // -------------------------------------------------------------------------
    axi_read(ADDR_RBR, 12'h050, read_data);

    if (read_data[7:0] !== rx_byte) begin
      $display("[%0t] ERROR: RX mismatch. Expected=0x%02h Got=0x%02h",
               $time, rx_byte, read_data[7:0]);
    end
    else begin
      $display("[%0t] PASS: RX data matches expected byte 0x%02h",
               $time, rx_byte);
    end

    // Final LSR check
    axi_read(ADDR_LSR, 12'h060, read_data);

    $display("");
    $display("==============================================================");
    $display("             AXI-LITE UART TEST COMPLETE");
    $display("             Inspect uart_tx_o / uart_rx_i");
    $display("             and AXI transactions in the waveform.");
    $display("==============================================================");
    $display("");

    #100;
    $finish;
  end

endmodule

`default_nettype wire
