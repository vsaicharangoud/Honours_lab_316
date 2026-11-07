# Test Plan Summary Table

| Test ID | Description | C Programming Part | SV Part | Scope (Internal/External) | Internal Interfaces | External Interfaces | Key Signals |
|:-------:|:------------|:-------------------|:-------|:--------------------------|:-------------------|:--------------------|:------------|
| TP-001 | Reset and Initialization Sequence | N/A | Reset controller, bus monitor | Internal | AXI4, AXI4-Lite | None | rst_n, clk, bus_valid, bus_ready |
| TP-002 | Clock Operation & Edge Synchronization | N/A | Clock generator, monitor | Internal | AXI4 | None | clk |
| TP-003 | Basic Instruction Fetch Access | N/A | IFU adapter BFM, read checker | Internal | AXI4 (64‑to‑32) | None | ifu_req, ifu_resp |
| TP-004 | Instruction Memory Boundary & Range | N/A | IFU adapter BFM, error detector | Internal | AXI4 (64‑to‑32) | None | addr, read_data, bus_error |
| TP-005 | Data Memory Read/Write Operations | N/A | LSU BFM, data checker | Internal | AXI4 (64‑to‑32) | None | lsu_req, lsu_resp |
| TP-006 | Data Memory Boundary & Aliasing | N/A | LSU BFM, alias detector | Internal | AXI4 (64‑to‑32) | None | addr, write_data |
| TP-007 | Crossbar Address Decoding | N/A | Crossbar BFM, select monitor | Internal | AXI4 crossbar | None | m0X_valid, addr |
| TP-008 | Single‑Beat & Burst Read Handshakes | N/A | LSU BFM, handshake monitor | Internal | AXI4 | None | ARVALID, ARREADY, RDATA, RLAST |
| TP-009 | Single‑Beat Write Handshakes | N/A | LSU BFM, write response monitor | Internal | AXI4 | None | AWVALID, WVALID, BVALID |
| TP-010 | Unmapped Address / Bus Error Handling | N/A | Bus error BFM | Internal | AXI4 | None | SLVERR, DECERR |
| TP-011 | UART Register Access & Baud Configuration | N/A | UART adapter BFM, register checker | Internal | AXI4‑Lite (UART) | UART (serial) | uart_addr, uart_wr, uart_rd |
| TP-012 | UART Serial Transmission Verification | N/A | UART transmitter model, UART monitor | External | AXI4‑Lite (UART) | UART (serial) | uart_txd_o |
| TP-013 | UART Serial Reception Verification | N/A | UART receiver model, UART monitor | External | AXI4‑Lite (UART) | UART (serial) | uart_rxd_i |
| TP-014 | UART Back‑to‑Back & Framing Error Checks | N/A | UART stress BFM | External | AXI4‑Lite (UART) | UART (serial) | uart_framing_err |
| TP-015 | Basic Timer Count & Compare Match | N/A | Timer BFM, interrupt monitor | Internal | AXI4 | None | timer_cnt, timer_irq |
| TP-016 | Timer Reset, Disable & PWM Output | N/A | Timer & PWM BFM | Internal | AXI4 | None | pwm_out, timer_enable |
| TP-017 | GPIO Direction Control & Output Drive | N/A | GPIO BFM, output monitor | Internal | AXI4 | None | gpio_oe, gpio_o |
| TP-018 | GPIO Input Sampling & Edge Detection | N/A | GPIO BFM, input monitor | Internal | AXI4 | None | gpio_i, gpio_intr |
| TP-019 | Packet FIFO Basic Write and Read | N/A | Packet source BFM, FIFO monitor | Internal | AXI‑Stream | None | s_axis_tdata, s_axis_tvalid, m_axis_tdata |
| TP-020 | FIFO Full, Empty & Watermark Flags | N/A | FIFO BFM, flag checker | Internal | AXI‑Stream | None | fifo_full, fifo_empty, fifo_watermark |
| TP-021 | FIFO Overflow Detection & Event Signaling | N/A | FIFO overflow BFM, overflow pulse monitor | Internal | AXI‑Stream | None | fifo_overflow_o |
| TP-022 | FIFO Backpressure & Flow Control Handshake | N/A | FIFO backpressure BFM, ready handshake monitor | Internal | AXI‑Stream | None | s_axis_tready, m_axis_tready |
| TP-023 | CRC Known‑Good Packet Verification | N/A | CRC engine BFM, checksum comparator | Internal | AXI‑Stream | None | crc_pass_o, crc_err_o |
| TP-024 | CRC Corrupted Packet & Error Detection | N/A | CRC error injection BFM | Internal | AXI‑Stream | None | crc_err_o |
| TP-025 | CRC Configuration & Reset Semantics | N/A | CRC register BFM | Internal | AXI4‑Lite (CRC) | None | crc_ctrl, crc_status |
| TP-026 | Packet Counter Basic Event Accounting | N/A | Counter BFM, event tally | Internal | AXI4‑Lite (Counter) | None | packet_received, packet_processed |
| TP-027 | Counter Error Event Statistics Verification | N/A | Counter BFM, error injection | Internal | AXI4‑Lite (Counter) | None | crc_error_cnt, fifo_overflow_cnt |
| TP-028 | Counter Control, Clear & Disable | N/A | Counter control BFM | Internal | AXI4‑Lite (Counter) | None | counter_ctrl, counter_en |
| TP-029 | Autonomous Valid Packet Processing (End‑to‑End) | Bare‑metal firmware (main.c) | Full testbench: packet source, FIFO, CRC, Counter, UART monitor | External | AXI4, AXI‑Stream, AXI4‑Lite | UART (serial console) | clk, rst_n, irq, uart_txd_o |
| TP-030 | System Corrupted Packet Handling (End‑to‑End) | Bare‑metal firmware (main.c) | Full testbench with error injection | External | AXI4, AXI‑Stream, AXI4‑Lite | UART (serial console) | irq, crc_err_o, uart_txd_o |
| TP-031 | Variable Packet Lengths & High Throughput | Bare‑metal firmware (main.c) | Packet generator with variable length, scoreboard | Internal | AXI‑Stream | None | s_axis_tlast, m_axis_tlast |
| TP-032 | FIFO Overflow System Recovery | Bare‑metal firmware (main.c) | Overflow injection BFM, recovery monitor | Internal | AXI‑Stream | None | fifo_overflow_o, irq |
| TP-033 | Concurrent CPU & Packet Streaming Stress | Bare‑metal firmware (main.c) | CPU memory BFM + packet stream BFM | Internal | AXI4, AXI‑Stream | None | cpu_mem_req, packet_flow |
| TP-034 | Vectored PIC Interrupt Verification | Bare‑metal firmware (interrupt handlers) | Interrupt BFM, ISR monitor | Internal | AXI4‑Lite (IRQ) | None | irq lines 1‑6 |
| TP-035 | Register Reset & Access Permissions | N/A | Register access BFM, permission checker | Internal | AXI4‑Lite | None | read_only_reg, write_mask |
| TP-036 | SoC Bare‑Metal Firmware Application Boot | Bare‑metal firmware (full application) | Full system testbench, UART console capture | External | AXI4, AXI‑Stream, AXI4‑Lite | UART (serial console) | rst_n, clk, irq, uart_txd_o |
