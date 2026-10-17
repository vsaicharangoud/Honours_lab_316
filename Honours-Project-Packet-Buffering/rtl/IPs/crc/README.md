# CRC-32 IP Core (Reliable Data Transport System SoC)

## 1. Overview
This directory contains the synthesizable RTL implementation and verification testbench for the **CRC-32 Hardware Integrity Verification IP Core**. It is integrated into the **Reliable Data Transport System SoC** at base address **`0x000A_0000`** (4 KB allocated memory region).

The IP supports two operational interfaces matching the SoC architecture:
* **Path A (Streaming Datapath)**: Receives packet words from the Packet FIFO via an AXI-Stream interface (`s_axis_*`), computes the IEEE 802.3 CRC-32 checksum in parallel, and detects packet transmission errors.
* **Path B (Processor Control/Status)**: Memory-mapped 32-bit AXI4-Lite slave interface enabling the RISC-V VeeR EL2 CPU to configure polynomials, inspect calculation results, monitor statistics counters, and service interrupts.

---

## 2. Directory Structure
```
rtl/ip/crc/
├── crc_defines.vh          # Register addresses, bitfields, and default polynomial macros
├── crc32_engine.v          # Parallel IEEE 802.3 CRC-32 computation engine (1 to 4 bytes/cycle)
├── crc_checker.v           # Packet datapath framing, comparator, and error/pass counters
├── crc_axi4lite_slave.v    # AXI4-Lite register interface mapped at 0x000A_0000
├── crc_top.v               # Top-level IP module integrating AXI-Lite & Stream interfaces
├── tb_crc_top.v            # Self-checking testbench covering all operational modes
├── run_sim.sh              # Simulation runner script using Synopsys VCS
└── README.md               # IP documentation and integration guide
```

---

## 3. Register Map (Base: `0x000A_0000`)

| Offset | Register Name | Type | Reset Value | Description |
| :--- | :--- | :---: | :---: | :--- |
| `+0x00` | **`CRC_CTRL`** | R/W | `0x0000_0011` | `[0]`: IP Enable (`1`=active)<br>`[1]`: Soft Reset (`1`=pulse reset)<br>`[2]`: Interrupt Enable on Done<br>`[3]`: Interrupt Enable on Error<br>`[4]`: Auto-clear CRC on next packet start |
| `+0x04` | **`CRC_STATUS`** | R/W1C | `0x0000_0000` | `[0]`: CRC Busy (`RO`)<br>`[1]`: CRC Done (`W1C`)<br>`[2]`: CRC Pass (`W1C`)<br>`[3]`: CRC Error / Mismatch (`W1C`)<br>`[5]`: Active IRQ Pending (`RO`) |
| `+0x08` | **`CRC_CALC_RESULT`** | RO | `0x0000_0000` | 32-bit hardware-computed CRC-32 result |
| `+0x0C` | **`CRC_EXP_RESULT`** | R/W | `0x0000_0000` | 32-bit expected CRC result (for register comparison mode) |
| `+0x10` | **`CRC_POLY`** | R/W | `0xEDB8_8320` | Reflected CRC polynomial (default IEEE 802.3 Ethernet) |
| `+0x14` | **`CRC_INIT_VAL`** | R/W | `0xFFFF_FFFF` | Initial CRC accumulator seed |
| `+0x18` | **`CRC_BYTE_COUNT`** | RO | `0x0000_0000` | Number of payload bytes processed in current packet |
| `+0x1C` | **`CRC_MANUAL_DATA`** | WO | `0x0000_0000` | Direct CPU write port to inject words without FIFO |
| `+0x20` | **`CRC_ERROR_COUNT`** | R/W1C | `0x0000_0000` | Cumulative corrupted packet counter |
| `+0x24` | **`CRC_PASS_COUNT`** | R/W1C | `0x0000_0000` | Cumulative valid packet counter |
| `+0x28` | **`CRC_MODE_CONFIG`** | R/W | `0x0000_0001` | `[1:0]`: `00`=Trailing FCS mode, `01`=Register mode, `10`=Compute-only |

---

## 4. Top-Level Port List (`crc_top.v`)

```verilog
module crc_top #(
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite Slave Interface (Base: 0x000A_0000)
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // Streaming Packet Datapath (From Packet FIFO)
    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // Dedicated Hardware Flags & Interrupt to SoC
    output wire        crc_pass_o,   // Pulse: Packet verified PASS
    output wire        crc_error_o,  // Pulse: Packet CRC mismatch
    output wire        crc_done_o,   // Pulse: Packet verification complete
    output wire        crc_busy_o,   // Level: Packet verification in progress
    output wire        irq_o         // Level: Interrupt to VeeR PIC
);
```

---

## 5. Verification & Running Simulation
To run the automated self-checking simulation using Synopsys VCS:
```bash
cd /home/student/Documents/316/Reliable_Data_Transport_System/rtl/ip/crc
./run_sim.sh
```
The testbench validates:
1. Standard IEEE 802.3 CRC-32 on `"123456789"` resulting in `0xCBF43926`.
2. AXI4-Lite register writes and reads.
3. Valid packet arrival asserting `crc_pass_o` and incrementing `pass_count`.
4. Corrupted packet arrival asserting `crc_error_o`, raising `irq_o`, and incrementing `error_count`.
5. Write-1-to-Clear (W1C) interrupt clearing.
