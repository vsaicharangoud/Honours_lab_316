// ============================================================================
// File   : tb/tb_soc_top.sv
// Project: RISC-V VeeR EL2 SoC – Hardware Packet Buffering & Data Integrity
//
// Purpose:
//   Top-level simulation testbench for soc_top.
//
//   Provides:
//     1. Clock (50 MHz = 20 ns period) and synchronous/asynchronous reset.
//     2. Firmware preloading: passes INIT_INSTR_HEX_FILE parameter to soc_top
//        so that axi_ram initialises the instruction RAM with program.hex.
//     3. UART Rx drive: holds uart_rx_i = 1 (idle / no data) so the firmware
//        never gets stuck waiting for a received byte.
//     4. Virtual UART monitor: watches uart_tx_o and decodes UART characters
//        at 115200 baud → prints to simulator console.
//     5. Hard simulation timeout ($finish) to prevent indefinite hang.
//        Default: 2 ms simulated time = 100,000 cycles @ 50 MHz.
//     6. Pass / Fail detection: simulation ends early and reports PASS when
//        the firmware UART output contains "[PASS] ALL TESTS COMPLETED".
//
//   export RV_ROOT=.../rtl/RISC-V-VeeR-EL2
//   vcs -full64 -sverilog \
//       +define+RV_OPENSOURCE +define+RV_BUILD_AXI4 \
//       +define+INIT_INSTR_HEX_FILE=\"sw/program.hex\" \
//       <all the same RTL files as before> \
//       tb/tb_soc_top.sv \
//       -top tb_soc_top \
//       -timescale=1ns/10ps -o simv_soc_top -l compile_soc_top.log
//
//   ./simv_soc_top
//
// ============================================================================

`timescale 1ns / 10ps
`default_nettype none

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "scripts/uart_uvm_tb/uart_if.sv"
`include "scripts/gpio_uvm_tb/gpio_if.sv"
`include "scripts/packet_fifo_uvm_tb/packet_fifo_if.sv"

`include "scripts/uart_uvm_tb/uart_pkg.sv"
import uart_pkg::*;

module tb_soc_top;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    // Path to firmware HEX file.  Override on the vcs command line:
    //   +define+INIT_INSTR_HEX_FILE=\"<path>\"
`ifndef INIT_INSTR_HEX_FILE
    `define INIT_INSTR_HEX_FILE "sw/program.hex"
`endif

    // Simulation timeout (ns).
    // Budget: ~700 UART chars × 87 µs/char ≈ 61 ms transmission time,
    // plus reset delay (0.41 ms), boot/execute overhead (~1 ms),
    // and TP-015 timer wait (~0.1 ms).  100 ms gives 1.5× margin.
    // Increase further only if new long-running tests are added.
`ifndef SIM_TIMEOUT_NS
    `define SIM_TIMEOUT_NS 100_000_000
`endif

    // UART baud rate for the virtual monitor.
`ifndef UART_BAUD
    `define UART_BAUD 115200
`endif

    // Clock period (ns): 50 MHz
    localparam real CLK_PERIOD   = 20.0;
    // Bit period (ns) for UART virtual monitor
    localparam real UART_BIT_NS  = 1_000_000_000.0 / `UART_BAUD; // ~8680 ns @ 115200

    // -----------------------------------------------------------------------
    // DUT Signals
    // -----------------------------------------------------------------------
    logic        clk;
    logic        rst_n;

    logic        uart_rx_i;
    logic        uart_tx_o;

    logic [31:0] gpio_i;
    logic [31:0] gpio_o;
    logic [31:0] gpio_dir_o;

    logic        timer_irq_o;
    logic        timer_match_o;
    logic        timer_pwm_o;

    // External packet stream (unused in this TB; tie-off with no valid data)
    logic [31:0] ext_axis_tdata;
    logic [3:0]  ext_axis_tkeep;
    logic        ext_axis_tlast;
    logic        ext_axis_tvalid;
    logic        ext_axis_tready;

    // Datapath status
    logic        fifo_full_o;
    logic        fifo_empty_o;
    logic        fifo_overflow_o;
    logic        crc_pass_o;
    logic        crc_error_o;
    logic        crc_done_o;
    logic        crc_busy_o;
    logic        packet_received_o;
    logic        packet_processed_o;

    // Trace
    logic [31:0] trace_pc_o;
    logic [31:0] trace_insn_o;
    logic        trace_valid_o;

    // -----------------------------------------------------------------------
    // UVM VIP Interfaces (from scripts/)
    // -----------------------------------------------------------------------
    uart_if         u_uart_if();
    gpio_if         u_gpio_if();
    packet_fifo_if  u_packet_fifo_if();

    // Interface clock binding
    assign u_uart_if.clk        = clk;
    assign u_gpio_if.clk        = clk;
    assign u_packet_fifo_if.clk = clk;

    // Connect UART VIP interface to DUT
    assign u_uart_if.UART_TX    = uart_tx_o;
    assign uart_rx_i            = u_uart_if.UART_RX;

    // Connect GPIO VIP interface to DUT
    assign gpio_i               = u_gpio_if.gpio_i;
    assign u_gpio_if.gpio_o     = gpio_o;
    assign u_gpio_if.gpio_oe    = gpio_dir_o;

    // Connect Packet FIFO VIP interface to DUT
    assign ext_axis_tdata       = u_packet_fifo_if.ext_axis_tdata;
    assign ext_axis_tvalid      = u_packet_fifo_if.ext_axis_tvalid;
    assign ext_axis_tlast       = u_packet_fifo_if.ext_axis_tlast;
    assign u_packet_fifo_if.ext_axis_tready = ext_axis_tready;

    // -----------------------------------------------------------------------
    // UVM Configuration Database – Register Virtual Interfaces for VIPs
    // -----------------------------------------------------------------------
    initial begin
        // UART VIP virtual interface registration
        uvm_config_db#(virtual uart_if)::set(null, "*", "vif", u_uart_if);
        uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", u_uart_if);

        // GPIO VIP virtual interface registration
        uvm_config_db#(virtual gpio_if)::set(null, "*", "vif", u_gpio_if);
        uvm_config_db#(virtual gpio_if)::set(null, "*", "gpio_vif", u_gpio_if);

        // Packet FIFO VIP virtual interface registration
        uvm_config_db#(virtual packet_fifo_if)::set(null, "*", "vif", u_packet_fifo_if);
        uvm_config_db#(virtual packet_fifo_if)::set(null, "*", "packet_fifo_vif", u_packet_fifo_if);

        $display("[TB] UVM virtual interfaces successfully registered into uvm_config_db");
    end

    // UVM Test runner
    initial begin
        string test_name;
        if ($value$plusargs("UVM_TESTNAME=%s", test_name)) begin
            $display("[TB] Starting UVM Test: %s", test_name);
            run_test();
        end else begin
            $display("[TB] Starting default UVM Test: uart_test");
            run_test("uart_test");
        end
    end

    // -----------------------------------------------------------------------
    // DUT Instantiation
    // -----------------------------------------------------------------------
    soc_top #(
        .INIT_INSTR_HEX_FILE (`INIT_INSTR_HEX_FILE),
        .INIT_DATA_HEX_FILE  ("")
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),

        .uart_rx_i           (uart_rx_i),
        .uart_tx_o           (uart_tx_o),

        .gpio_i              (gpio_i),
        .gpio_o              (gpio_o),
        .gpio_dir_o          (gpio_dir_o),

        .timer_irq_o         (timer_irq_o),
        .timer_match_o       (timer_match_o),
        .timer_pwm_o         (timer_pwm_o),

        .ext_axis_tdata      (ext_axis_tdata),
        .ext_axis_tkeep      (ext_axis_tkeep),
        .ext_axis_tlast      (ext_axis_tlast),
        .ext_axis_tvalid     (ext_axis_tvalid),
        .ext_axis_tready     (ext_axis_tready),

        .fifo_full_o         (fifo_full_o),
        .fifo_empty_o        (fifo_empty_o),
        .fifo_overflow_o     (fifo_overflow_o),
        .crc_pass_o          (crc_pass_o),
        .crc_error_o         (crc_error_o),
        .crc_done_o          (crc_done_o),
        .crc_busy_o          (crc_busy_o),
        .packet_received_o   (packet_received_o),
        .packet_processed_o  (packet_processed_o),

        .trace_pc_o          (trace_pc_o),
        .trace_insn_o        (trace_insn_o),
        .trace_valid_o       (trace_valid_o)
    );

    // -----------------------------------------------------------------------
    // Clock Generation – 50 MHz (20 ns period)
    // -----------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // -----------------------------------------------------------------------
    // Reset Sequence
    // -----------------------------------------------------------------------
    initial begin
        rst_n    = 1'b0;
        u_gpio_if.gpio_i                 = 32'h0;
        u_uart_if.UART_RX                = 1'b1;      // UART Rx idle = logic 1
        // External packet stream: keep tvalid low so no unsolicited data
        u_packet_fifo_if.ext_axis_tdata  = 32'h0;
        ext_axis_tkeep                   = 4'hF;
        u_packet_fifo_if.ext_axis_tlast  = 1'b0;
        u_packet_fifo_if.ext_axis_tvalid = 1'b0;

        // Hold reset for 20 clock cycles
        repeat (20) @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        $display("[TB] Reset de-asserted at time %0t ns", $realtime);
    end

    // -----------------------------------------------------------------------
    // Simulation Timeout Watchdog
    // -----------------------------------------------------------------------
    initial begin
        #(`SIM_TIMEOUT_NS);
        $display("[TB] *** SIMULATION TIMEOUT after %0d ns ***", `SIM_TIMEOUT_NS);
        $display("[TB] FAIL: Simulation timed out – firmware did not complete.");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Virtual UART Monitor
    // Samples uart_tx_o and reconstructs ASCII characters.
    // Characters are printed to the simulator console.  A line containing
    // "[PASS] ALL TESTS COMPLETED" ends the simulation with success.
    // -----------------------------------------------------------------------
    // Buffer to accumulate UART output lines
    string uart_line = "";

    task automatic uart_monitor();
        // Wait for start bit (falling edge on uart_tx_o, which idles at 1)
        @(negedge uart_tx_o);

        // Sample in the middle of each bit: wait 1.5 bit periods for first data bit
        #(UART_BIT_NS * 1.5);

        begin
            automatic byte char_val = 8'h00;
            automatic int  bit_idx;

            // Sample 8 data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if (uart_tx_o) char_val[bit_idx] = 1'b1;
                else           char_val[bit_idx] = 1'b0;
                if (bit_idx < 7)
                    #(UART_BIT_NS);
            end

            // Wait through stop bit
            #(UART_BIT_NS);

            // Print / accumulate character
            if (char_val == 8'h0A || char_val == 8'h0D) begin
                // Newline – flush the line buffer
                if (uart_line.len() > 0) begin
                    $display("[UART] %s", uart_line);
                    // Check for pass/fail markers
                    if (uart_line.substr(0, uart_line.len()-1) == "[PASS] ALL TESTS COMPLETED") begin
                        $display("[TB] *** SIMULATION PASSED ***");
                        $finish;
                    end
                    uart_line = "";
                end
            end else begin
                uart_line = {uart_line, string'(char_val)};
            end
        end
    endtask

    // Run the UART monitor in a continuous loop
    initial begin
        // Wait until after reset
        wait (rst_n === 1'b1);
        $display("[TB] UART monitor started. Baud = %0d, Bit period = %0.1f ns",
                 `UART_BAUD, UART_BIT_NS);
        forever begin
            uart_monitor();
        end
    end

    // -----------------------------------------------------------------------
    // Optional: dump waveforms
    // Compile with +define+DUMP_FSDB or +define+DUMP_VPD to enable.
    // -----------------------------------------------------------------------
`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_soc_top.fsdb");
        $fsdbDumpvars(0, tb_soc_top);
    end
`elsif DUMP_VPD
    initial begin
        $vcdplusfile("tb_soc_top.vpd");
        $vcdpluson;
    end
`endif

    // -----------------------------------------------------------------------
    // Trace: Print every committed instruction address (optional verbose mode)
    // -----------------------------------------------------------------------
`ifdef VERBOSE_TRACE
    always @(posedge clk) begin
        if (trace_valid_o)
            $display("[TRACE] PC=0x%08X  INSN=0x%08X", trace_pc_o, trace_insn_o);
    end
`endif

    // -----------------------------------------------------------------------
    // DEBUG PROBE: Monitor IFU and LSU AXI bus activity (first 200 cycles
    // after reset). This helps diagnose bus deadlocks without VERBOSE_TRACE.
    // Uses hierarchical references into the DUT.
    // -----------------------------------------------------------------------
    integer dbg_cycle_count;
    integer dbg_ifu_ar_count;
    integer dbg_lsu_ar_count;
    integer dbg_lsu_aw_count;
    // Track UART LSR read responses to diagnose THRE polling loop.
    integer dbg_uart_lsr_count;
    // Track M02 boundary AR handshakes (interconnect->adapter)
    integer dbg_m02_ar_count;
    // Track M02 boundary R handshakes (adapter->interconnect)
    integer dbg_m02_r_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            dbg_cycle_count    <= 0;
            dbg_ifu_ar_count   <= 0;
            dbg_lsu_ar_count   <= 0;
            dbg_lsu_aw_count   <= 0;
            dbg_uart_lsr_count <= 0;
            dbg_m02_ar_count   <= 0;
            dbg_m02_r_count    <= 0;
        end else begin
            dbg_cycle_count <= dbg_cycle_count + 1;

            // Print first 20 IFU read requests
            if (u_dut.s00_axi_arvalid && u_dut.s00_axi_arready && dbg_ifu_ar_count < 20) begin
                $display("[DBG-IFU] AR #%0d: addr=0x%08X arlen=%0d arsize=%0d time=%0t",
                         dbg_ifu_ar_count, u_dut.s00_axi_araddr, u_dut.s00_axi_arlen, u_dut.s00_axi_arsize, $realtime);
                dbg_ifu_ar_count <= dbg_ifu_ar_count + 1;
            end

            // Print first 20 LSU read requests
            if (u_dut.s01_axi_arvalid && u_dut.s01_axi_arready && dbg_lsu_ar_count < 20) begin
                $display("[DBG-LSU-RD] AR #%0d: addr=0x%08X arlen=%0d time=%0t",
                         dbg_lsu_ar_count, u_dut.s01_axi_araddr, u_dut.s01_axi_arlen, $realtime);
                dbg_lsu_ar_count <= dbg_lsu_ar_count + 1;
            end

            // Print first 20 LSU write requests
            if (u_dut.s01_axi_awvalid && u_dut.s01_axi_awready && dbg_lsu_aw_count < 20) begin
                $display("[DBG-LSU-WR] AW #%0d: addr=0x%08X awlen=%0d wdata=0x%08X time=%0t",
                         dbg_lsu_aw_count, u_dut.s01_axi_awaddr, u_dut.s01_axi_awlen, u_dut.s01_axi_wdata, $realtime);
                dbg_lsu_aw_count <= dbg_lsu_aw_count + 1;
            end

            // ----------------------------------------------------------------
            // M02 BOUNDARY PROBES: interconnect <-> UART adapter
            // ----------------------------------------------------------------
            // AR handshake at M02 (interconnect routes AR to adapter)
            if (u_dut.m02_arvalid && u_dut.m02_arready && dbg_m02_ar_count < 5) begin
                $display("[DBG-M02-AR] #%0d: addr=0x%08X arready=%0b time=%0t",
                         dbg_m02_ar_count,
                         u_dut.m02_araddr,
                         u_dut.m02_arready,
                         $realtime);
                dbg_m02_ar_count <= dbg_m02_ar_count + 1;
            end

            // R handshake at M02 (adapter returns data to interconnect)
            if (u_dut.m02_rvalid && u_dut.m02_rready && dbg_m02_r_count < 5) begin
                $display("[DBG-M02-R] #%0d: rdata=0x%08X rresp=%0d (LSR[5]=THRE=%0b LSR[6]=TEMT=%0b) time=%0t",
                         dbg_m02_r_count,
                         u_dut.m02_rdata,
                         u_dut.m02_rresp,
                         u_dut.m02_rdata[5],
                         u_dut.m02_rdata[6],
                         $realtime);
                dbg_m02_r_count <= dbg_m02_r_count + 1;
            end

            // Periodic M02 status dump
            if (dbg_cycle_count == 500) begin
                $display("[DBG-M02-STATUS] t=%0t: m02_arvalid=%0b m02_arready=%0b m02_rvalid=%0b m02_rready=%0b",
                         $realtime, u_dut.m02_arvalid, u_dut.m02_arready, u_dut.m02_rvalid, u_dut.m02_rready);
                $display("[DBG-ADAPTER-STATUS] t=%0t: read_active=%0b uart_arvalid_reg=%0b read_resp_valid_reg=%0b",
                         $realtime,
                         u_dut.u_uart_adapter.read_active,
                         u_dut.u_uart_adapter.uart_arvalid_reg,
                         u_dut.u_uart_adapter.read_resp_valid_reg);
                $display("[DBG-UART-RSTATE] t=%0t: read_state=%0d axi_arready=%0b axi_rvalid=%0b axi_rdata=0x%08X",
                         $realtime,
                         u_dut.u_uart.read_state,
                         u_dut.u_uart.axi_arready,
                         u_dut.u_uart.axi_rvalid,
                         u_dut.u_uart.axi_rdata);
            end

            if (dbg_cycle_count == 1000) begin
                $display("[DBG-M02-STATUS] t=%0t: m02_arvalid=%0b m02_arready=%0b m02_rvalid=%0b m02_rready=%0b",
                         $realtime, u_dut.m02_arvalid, u_dut.m02_arready, u_dut.m02_rvalid, u_dut.m02_rready);
                $display("[DBG-ADAPTER-STATUS] t=%0t: read_active=%0b uart_arvalid_reg=%0b read_resp_valid_reg=%0b",
                         $realtime,
                         u_dut.u_uart_adapter.read_active,
                         u_dut.u_uart_adapter.uart_arvalid_reg,
                         u_dut.u_uart_adapter.read_resp_valid_reg);
                $display("[DBG-UART-RSTATE] t=%0t: read_state=%0d axi_arready=%0b axi_rvalid=%0b axi_rdata=0x%08X",
                         $realtime,
                         u_dut.u_uart.read_state,
                         u_dut.u_uart.axi_arready,
                         u_dut.u_uart.axi_rvalid,
                         u_dut.u_uart.axi_rdata);
                $display("[DBG-UART-LSR] t=%0t: available_write_space_int=%0b tx_fifo_reset_int=%0b tx_status_int=%0b",
                         $realtime,
                         u_dut.u_uart.available_write_space_int,
                         u_dut.u_uart.tx_fifo_reset_int,
                         u_dut.u_uart.tx_status_int);
            end

            // Print UART adapter read response (actual RDATA returned for UART reads).
            // Tap the adapter's read_resp_valid_reg rising edge — captures every time
            // the adapter completes a UART read and has data ready for the CPU.
            // This shows exactly what LSR value the CPU sees.
            if (u_dut.u_uart_adapter.read_resp_valid_reg &&
                !$past(u_dut.u_uart_adapter.read_resp_valid_reg, 1) &&
                dbg_uart_lsr_count < 5) begin
                $display("[DBG-UART-RD] #%0d: UART adapter rdata=0x%08X (LSR[5]=THRE=%0b, LSR[6]=TEMT=%0b) time=%0t",
                         dbg_uart_lsr_count,
                         u_dut.u_uart_adapter.read_data_reg,
                         u_dut.u_uart_adapter.read_data_reg[5],
                         u_dut.u_uart_adapter.read_data_reg[6],
                         $realtime);
                dbg_uart_lsr_count <= dbg_uart_lsr_count + 1;
            end

            // Also print the raw UART internal signals once (first time ARVALID seen).
            // This diagnoses whether available_write_space_int is actually being set.
            if (dbg_uart_lsr_count == 0 && u_dut.u_uart_adapter.uart_arvalid_reg) begin
                $display("[DBG-UART-INT] available_write_space_int=%0b tx_fifo_reset=%0b time=%0t",
                         u_dut.u_uart.available_write_space_int,
                         u_dut.u_uart.tx_fifo_reset_int,
                         $realtime);
            end

            // After 10000 cycles, print summary
            if (dbg_cycle_count == 10000) begin
                $display("[DBG] After 10000 cycles: IFU AR count=%0d, LSU AR count=%0d, LSU AW count=%0d",
                         dbg_ifu_ar_count, dbg_lsu_ar_count, dbg_lsu_aw_count);
                $display("[DBG] M02 AR handshakes=%0d, M02 R handshakes=%0d",
                         dbg_m02_ar_count, dbg_m02_r_count);
            end

            // After 50000 cycles, print every 50000 cycles
            if (dbg_cycle_count > 10000 && (dbg_cycle_count % 50000) == 0) begin
                $display("[DBG] Cycle %0d: IFU AR count=%0d, LSU AR count=%0d, LSU AW count=%0d",
                         dbg_cycle_count, dbg_ifu_ar_count, dbg_lsu_ar_count, dbg_lsu_aw_count);
            end
        end
    end

endmodule

`default_nettype wire
