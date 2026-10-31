# AXI4 RAM IP Core — RISC-V VeeR EL2 SoC Packet Buffering

## 1. Overview
The AXI4 RAM IP Core provides high-performance, single-cycle synchronous memory for the RISC-V VeeR EL2 SoC. It is parameterized to serve both as:
- **Instruction Memory (M00):** `0x0000_0000` - `0x0000_FFFF` (64KB)
- **Data Memory (M01):** `0x0001_0000` - `0x0001_FFFF` (64KB)

## 2. Features
- Full AXI4 protocol compliance
- Independent 4-byte strobe write enables (`s_axi_wstrb[3:0]`)
- Multi-beat INCR burst handling with `s_axi_rlast` generation (mandatory for VeeR IFU instruction cacheline fills)
- Fast zero-wait-state memory access
- Optional hex file preloading (`INIT_HEX_FILE` parameter)

## 3. Hardware Ports
- Clock & Reset: `clk`, `rst` (active-high synchronous)
- AXI4 Subordinate Write Channels: `awid`, `awaddr`, `awlen`, `awsize`, `awburst`, `awvalid`, `awready`, `wdata`, `wstrb`, `wlast`, `wvalid`, `wready`, `bid`, `bresp`, `bvalid`, `bready`
- AXI4 Subordinate Read Channels: `arid`, `araddr`, `arlen`, `arsize`, `arburst`, `arvalid`, `arready`, `rid`, `rdata`, `rresp`, `rlast`, `rvalid`, `rready`

## 4. Verification
Run `./run_sim.sh` to compile and execute the self-checking testbench (`tb_axi_ram.v`) with Synopsys VCS.
All tests pass.
