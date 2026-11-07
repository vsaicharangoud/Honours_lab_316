# SoC Project – Current Status

**Last updated:** 2026-11-07 (session ended due to throttle)

---

## 1. Files Modified This Session (2026-11-07)

| File | Change | Timestamp |
|------|--------|-----------|
| `tb/tb_soc_top.sv` | Added UART LSR debug probe (see §3) | 2026-11-07 10:20 |

No RTL, firmware, linker, or test-case files were modified.

---

## 2. Simulation Binary Status

| Item | Status |
|------|--------|
| `simv_soc_top` binary | **DOES NOT EXIST** – was deleted between sessions |
| `simv_soc_top.daidir/` | Present (from Oct 31 compile) – stale, must not be used |
| Last successful `simv_soc_top` | Compiled 2026-10-31 17:52 by VCS U-2023.03_Full64 |
| `sim_soc_top.log` | Present – from the most recent simulation run (2026-11-07 10:09) |
| `compile_soc_top.log` | Present but incomplete – latest attempt (2026-11-07 10:21) failed due to license error before any RTL was parsed |

The `simv_soc_top` binary must be rebuilt from source before the next simulation run.

---

## 3. UART LSR Debug Probe – `tb/tb_soc_top.sv`

The debug probe was **successfully added and saved** to `tb/tb_soc_top.sv`
(confirmed by file read; last modified 2026-11-07 10:20).

### What the probe does

Two new probes were added inside the existing `always @(posedge clk)` debug block:

**Probe 1 – UART adapter RDATA capture**
Fires on the rising edge of `u_dut.u_uart_adapter.read_resp_valid_reg` (i.e. every time
the adapter completes a UART read transaction and presents data to the CPU).
Prints the first 5 occurrences with:
- Raw `read_data_reg[31:0]`
- `read_data_reg[5]` = THRE bit
- `read_data_reg[6]` = TEMT bit
- Simulation timestamp

```
[DBG-UART-RD] #N: UART adapter rdata=0xXXXXXXXX (LSR[5]=THRE=X, LSR[6]=TEMT=X) time=...
```

**Probe 2 – UART internal state on first ARVALID**
Fires once, on the first clock when `uart_arvalid_reg` is asserted, printing:
- `u_dut.u_uart.available_write_space_int` – the raw THRE source signal
- `u_dut.u_uart.tx_fifo_reset_int` – TX FIFO soft-reset state

```
[DBG-UART-INT] available_write_space_int=X tx_fifo_reset=X time=...
```

A new counter `dbg_uart_lsr_count` was added alongside the existing
`dbg_cycle_count / dbg_ifu_ar_count / dbg_lsu_ar_count / dbg_lsu_aw_count` counters.

### Purpose

These two probes will confirm exactly:
1. Whether the UART returns THRE=0 to the CPU (RDATA has bit 5 clear), or
2. Whether THRE=1 is returned but the CPU still loops (data path / VeeR extract bug).

---

## 4. UART Debugging Findings (Static RTL Analysis)

### 4.1 Confirmed correct items

| Item | Evidence |
|------|----------|
| Address routing | Log: LSU reads `0x00020014` → interconnect routes to M02 (UART, 0x00020000/12) ✓ |
| Adapter address mapping | `uart_read_addr_reg = s_axi_araddr[4:0] = 0x14` → UART top uses `addr[4:2] = 0x14[4:2] = 3'b101 = 5 = UART_LSR` ✓ |
| MRAC sideeffect | `start.S` sets `MRAC = 0x00000002` (bit 1), `csr_idx = {addr[31:28], 1'b1} = {0,1} = 1` → `MRAC[1]=1` → sideeffect for region 0 ✓ |
| LSU sends actual address | Log confirms AR at `0x00020014` (not 8-byte-aligned `0x00020010`) ✓ |
| UART FSM sync gating fix | `axi_sync_rden` gate was already removed; outputs assigned directly from FSM ✓ |
| CPU completes reads | 20 separate AR handshakes logged; period ≈ 1.5–2.2 µs each; CPU is getting responses ✓ |
| TX FIFO reset value | `available_write_space <= 1'b1` on both `~arstn_i` and `else if (rst_i)` in FIFO 3'b111 case ✓ |

### 4.2 Unconfirmed / suspected items (need debug probe output)

| Question | Status |
|----------|--------|
| Is THRE bit actually 0 in the returned RDATA? | **UNCONFIRMED** – static analysis predicts THRE=1 but simulation shows loop never exits |
| Does VCS correctly elaborate the `generate case(PORT_EN)` FIFO status register? | Unverified |
| Is `available_write_space_int` = 0 at runtime? | Unverified |
| Does `read_data_reg` in the adapter correctly hold the UART's RDATA? | Unverified |

### 4.3 Known secondary issue (not the polling blocker)

`_UART_MAIN_CLOCK_FREQ_` defaults to 100 MHz when `FPGA_FULL` is not defined.
`UART_BAUDRATE_DIV_INIT = 100_000_000 / 115200 = 868`.
With the 50 MHz SoC clock: actual baud rate = 50 MHz / 868 ≈ 57 600 baud (half of 115 200).
This causes **wrong baud rate** but does **not** affect THRE – the TX FIFO available-space
logic is independent of baud rate.
Fix: add `+define+FPGA_FULL` to the VCS compile command (already included in the new command below).

### 4.4 Static analysis summary

From reading all relevant RTL (`axi_internal_fifo.v`, `axi_uart_top.v`,
`axi4_to_axi4lite_uart_adapter.v`, `veer_lsu_axi64_to_axi32_wrapper.v`,
`soc_top.v`, `tb_soc_top.sv`, `start.S`, `uart.h`):

- UART TX FIFO (PORT_EN=3'b111, AXI_FIFO_DEPTH=32) resets `available_write_space` to
  1'b1 asynchronously and holds it at 1'b1 during soft-reset (`tx_fifo_reset_int=1`).
- `available_write_space_int = tx_status_int[AXI_FIFO_ADDR+1] = tx_status_int[6]` maps to
  that register.
- `uart_lsr_reg_int[5]` (THRE) is a continuous assign driven by `available_write_space_int`.
- Static analysis predicts THRE=1 from power-on. **However**, the simulation shows the
  THRE loop never exits, which means either:
  (a) THRE is actually 0 in simulation (VCS elaboration issue with `generate case`, or
      a timing/initialization bug not visible in static analysis), **or**
  (b) THRE=1 is returned but does not propagate correctly through the 64-to-32-bit
      LSU wrapper's read data reconstruction.
- The debug probe added to the TB will distinguish these two cases.

---

## 5. VCS Compilation Command (with FPGA_FULL + debug probe)

Run from the project root `/home/student/Documents/HONOURS_316/316/soc_project_packet_buffering`:

```bash
export VCS_HOME=/home/student/snps_tools_target/vcs/U-2023.03
export PATH=$VCS_HOME/bin:$PATH
export SNPSLMD_LICENSE_FILE=27021@14.139.1.126
export LM_LICENSE_FILE=27021@14.139.1.126

vcs -full64 -sverilog \
  +define+RV_OPENSOURCE +define+RV_BUILD_AXI4 +define+FPGA_FULL \
  +define+INIT_INSTR_HEX_FILE=\"sw/program.hex\" \
  +incdir+rtl/RISC-V-VeeR-EL2/design/lib \
  +incdir+rtl/RISC-V-VeeR-EL2/design/include \
  +incdir+rtl/RISC-V-VeeR-EL2/snapshots/default \
  +incdir+rtl/RISC-V-VeeR-EL2/testbench \
  +incdir+rtl/wrappers \
  +incdir+rtl/IPs/timer \
  +incdir+rtl/IPs/gpio \
  +incdir+rtl/IPs/fifo \
  +incdir+rtl/IPs/crc \
  +incdir+rtl/IPs/UART_IP/src/include \
  rtl/RISC-V-VeeR-EL2/snapshots/default/common_defines.vh \
  rtl/RISC-V-VeeR-EL2/design/include/el2_def.sv \
  rtl/RISC-V-VeeR-EL2/snapshots/default/el2_pdef.vh \
  -f rtl/RISC-V-VeeR-EL2/testbench/flist \
  rtl/wrappers/veer_lsu_axi64_to_axi32_wrapper.v \
  rtl/wrappers/veer_ifu_axi64_to_axi32_wrapper.v \
  rtl/cpu/veer_cpu_subsystem.sv \
  rtl/adapters/arbiter.v \
  rtl/cpu/priority_encoder.v \
  rtl/interconnect/axi_interconnect.v \
  rtl/interconnect/axi_interconnect_wrap_3x8.v \
  rtl/adapters/axi4_to_axi4lite_uart_adapter.v \
  rtl/adapters/axi4_to_axi4lite_generic_adapter.v \
  rtl/IPs/axi_ram/axi_ram.v \
  rtl/IPs/timer/timer_core.v \
  rtl/IPs/timer/timer_axi4lite.v \
  rtl/IPs/timer/timer_top.v \
  rtl/IPs/gpio/gpio_core.v \
  rtl/IPs/gpio/gpio_axi4lite.v \
  rtl/IPs/gpio/gpio_top.v \
  rtl/IPs/fifo/fifo_mem.v \
  rtl/IPs/fifo/sync_ptr.v \
  rtl/IPs/fifo/fifo_diag.v \
  rtl/IPs/fifo/wr_domain.v \
  rtl/IPs/fifo/rd_domain.v \
  rtl/IPs/fifo/async_fifo_top.v \
  rtl/IPs/fifo/fifo_axi4lite_slave.v \
  rtl/IPs/fifo/packet_fifo_top.v \
  rtl/IPs/crc/crc32_engine.v \
  rtl/IPs/crc/crc_checker.v \
  rtl/IPs/crc/crc_axi4lite_slave.v \
  rtl/IPs/crc/crc_top.v \
  rtl/IPs/UART_IP/src/rtl/axi_internal_fifo.v \
  rtl/IPs/UART_IP/src/rtl/uart_controller.v \
  rtl/IPs/UART_IP/src/rtl/uart_parity_bit_compute.v \
  rtl/IPs/UART_IP/src/rtl/uart_receiver.v \
  rtl/IPs/UART_IP/src/rtl/uart_transmitter.v \
  rtl/IPs/UART_IP/src/rtl/axi_uart_top.v \
  rtl/packet_counter_axi.v \
  rtl/IPs/packet_source/packet_source.v \
  rtl/soc_top.v \
  tb/tb_soc_top.sv \
  -top tb_soc_top \
  -timescale=1ns/10ps \
  -o simv_soc_top \
  -l compile_soc_top.log
```

**Key difference vs Oct 31 compile command:** `+define+FPGA_FULL` was added.
Everything else is identical to the command recorded in `simv_soc_top.daidir/vcs_rebuild`.

Then run:
```bash
./simv_soc_top -l sim_soc_top.log
```

---

## 6. VCS_HOME and License Configuration Attempts

### What was tried in this session

| Attempt | VCS_HOME | LM_LICENSE_FILE | Result |
|---------|----------|-----------------|--------|
| 1 | Not set | Not set | `Cannot find 'vcsMsgReport' script in /bin` – VCS_HOME required |
| 2 | `/home/student/snps_tools_target/vcs/U-2023.03` | Not set | `Cannot find license file` |
| 3 | `/home/student/snps_tools_target/vcs/U-2023.03` | `/home/student/snps_tools_target/verdi/U-2023.03-SP1/share/edrServer/license.lic` | `Fatal License Error. Invalid license file syntax.` |
| 4 | `/home/student/snps_tools_target/vcs/U-2023.03` | `27020@localhost` | `Cannot find license file` (server not on localhost:27020) |

### Correct configuration (discovered from IP run_sim.sh scripts)

From `rtl/IPs/timer/run_sim.sh` (which ran successfully in previous sessions):

```bash
export VCS_HOME=/home/student/snps_tools_target/vcs/U-2023.03
export PATH=$VCS_HOME/bin:$PATH
export SNPSLMD_LICENSE_FILE=27021@14.139.1.126
export LM_LICENSE_FILE=27021@14.139.1.126
```

The license server is at `14.139.1.126:27021`.

### Current license error

The last compile attempt (`compile_soc_top.log`, 2026-11-07 10:21) showed only the
standard VCS header and terminated in 0.057 seconds with no RTL parsing. The terminal
output from that attempt reported:

```
Fatal License Error.
Invalid license file syntax.
Make sure that your SNPSLMD_LICENSE_FILE points to the correct server
```

This occurred when `SNPSLMD_LICENSE_FILE` was set to a `.lic` file path instead of a
`port@host` string. The correct value is `27021@14.139.1.126`.

**The session was throttled before the correct license environment could be applied
and a compile attempted.**

---

## 7. Next Steps

### Step 1 – Compile (requires network access to `14.139.1.126:27021`)

```bash
cd /home/student/Documents/HONOURS_316/316/soc_project_packet_buffering

export VCS_HOME=/home/student/snps_tools_target/vcs/U-2023.03
export PATH=$VCS_HOME/bin:$PATH
export SNPSLMD_LICENSE_FILE=27021@14.139.1.126
export LM_LICENSE_FILE=27021@14.139.1.126

vcs -full64 -sverilog \
  +define+RV_OPENSOURCE +define+RV_BUILD_AXI4 +define+FPGA_FULL \
  +define+INIT_INSTR_HEX_FILE=\"sw/program.hex\" \
  +incdir+rtl/RISC-V-VeeR-EL2/design/lib \
  +incdir+rtl/RISC-V-VeeR-EL2/design/include \
  +incdir+rtl/RISC-V-VeeR-EL2/snapshots/default \
  +incdir+rtl/RISC-V-VeeR-EL2/testbench \
  +incdir+rtl/wrappers +incdir+rtl/IPs/timer +incdir+rtl/IPs/gpio \
  +incdir+rtl/IPs/fifo +incdir+rtl/IPs/crc \
  +incdir+rtl/IPs/UART_IP/src/include \
  rtl/RISC-V-VeeR-EL2/snapshots/default/common_defines.vh \
  rtl/RISC-V-VeeR-EL2/design/include/el2_def.sv \
  rtl/RISC-V-VeeR-EL2/snapshots/default/el2_pdef.vh \
  -f rtl/RISC-V-VeeR-EL2/testbench/flist \
  rtl/wrappers/veer_lsu_axi64_to_axi32_wrapper.v \
  rtl/wrappers/veer_ifu_axi64_to_axi32_wrapper.v \
  rtl/cpu/veer_cpu_subsystem.sv rtl/adapters/arbiter.v \
  rtl/cpu/priority_encoder.v rtl/interconnect/axi_interconnect.v \
  rtl/interconnect/axi_interconnect_wrap_3x8.v \
  rtl/adapters/axi4_to_axi4lite_uart_adapter.v \
  rtl/adapters/axi4_to_axi4lite_generic_adapter.v \
  rtl/IPs/axi_ram/axi_ram.v rtl/IPs/timer/timer_core.v \
  rtl/IPs/timer/timer_axi4lite.v rtl/IPs/timer/timer_top.v \
  rtl/IPs/gpio/gpio_core.v rtl/IPs/gpio/gpio_axi4lite.v \
  rtl/IPs/gpio/gpio_top.v rtl/IPs/fifo/fifo_mem.v \
  rtl/IPs/fifo/sync_ptr.v rtl/IPs/fifo/fifo_diag.v \
  rtl/IPs/fifo/wr_domain.v rtl/IPs/fifo/rd_domain.v \
  rtl/IPs/fifo/async_fifo_top.v rtl/IPs/fifo/fifo_axi4lite_slave.v \
  rtl/IPs/fifo/packet_fifo_top.v rtl/IPs/crc/crc32_engine.v \
  rtl/IPs/crc/crc_checker.v rtl/IPs/crc/crc_axi4lite_slave.v \
  rtl/IPs/crc/crc_top.v \
  rtl/IPs/UART_IP/src/rtl/axi_internal_fifo.v \
  rtl/IPs/UART_IP/src/rtl/uart_controller.v \
  rtl/IPs/UART_IP/src/rtl/uart_parity_bit_compute.v \
  rtl/IPs/UART_IP/src/rtl/uart_receiver.v \
  rtl/IPs/UART_IP/src/rtl/uart_transmitter.v \
  rtl/IPs/UART_IP/src/rtl/axi_uart_top.v \
  rtl/packet_counter_axi.v rtl/IPs/packet_source/packet_source.v \
  rtl/soc_top.v tb/tb_soc_top.sv \
  -top tb_soc_top -timescale=1ns/10ps \
  -o simv_soc_top -l compile_soc_top.log
```

### Step 2 – Simulate

```bash
./simv_soc_top -l sim_soc_top.log
```

### Step 3 – Interpret debug output

Look for these lines in `sim_soc_top.log`:

```
[DBG-UART-INT] available_write_space_int=X tx_fifo_reset=X ...
[DBG-UART-RD] #0: UART adapter rdata=0xXXXXXXXX (LSR[5]=THRE=X, LSR[6]=TEMT=X) ...
```

**If THRE=0:** The TX FIFO `available_write_space` register is 0 in simulation despite
static analysis predicting 1. Root cause is likely a VCS elaboration issue with the
`generate case(PORT_EN)` block, or the `tx_fifo_reset_int` never being deasserted.
Fix: initialise `tx_fifo_reset_int` to 0 in the UART write FSM reset state instead of 1,
or override the THRE signal with a direct tie to `(~tx_fifo_full_int)`.

**If THRE=1:** The UART is returning the correct value, but the 64-to-32-bit LSU
wrapper or VeeR's read-data extraction is failing. Likely cause: `rd_addr[2]` routing
error — address `0x0002_0014` has bit 2 = 1, so rdata goes to `rdata64[63:32]`, but
VeeR may not be reading that half. Investigate `veer_lsu_axi64_to_axi32_wrapper.v`
rdata reconstruction or VeeR's `buf_data_in` extraction.

---

## 8. Previously Modified Files (sessions prior to 2026-11-07)

These were modified in earlier sessions and must not be reverted:

| File | Modification |
|------|-------------|
| `tb/tb_soc_top.sv` | Complete replacement of old tb_lsu_axi_interconnect_uart.v with full SoC testbench; added IFU/LSU AXI debug probes; simulation timeout 100 ms (default) |
| `rtl/soc_top.v` | Full SoC integration: VeeR CPU subsystem, 3x8 interconnect, all IPs, UART adapter; MRAC configuration |
| `rtl/cpu/veer_cpu_subsystem.sv` | VeeR EL2 CPU subsystem with LSU 64→32 and IFU 64→32 bridges; `lsu_bus_clk_en=1'b1` |
| `rtl/adapters/axi4_to_axi4lite_uart_adapter.v` | AXI4→AXI4-Lite bridge for UART; holds ARVALID until RVALID; fixes AWVALID+WVALID simultaneous requirement |
| `rtl/IPs/UART_IP/src/rtl/axi_uart_top.v` | Removed `axi_sync_rden` gating from `axi_rvalid_o`; added default case to read FSM; output assigns use FSM registers directly |
| `rtl/wrappers/veer_lsu_axi64_to_axi32_wrapper.v` | New file: 64→32 bit LSU AXI bridge with correct data lane selection and RDATA reconstruction |
| `rtl/wrappers/veer_ifu_axi64_to_axi32_wrapper.v` | New file: 64→32 bit IFU AXI bridge |
| `rtl/interconnect/axi_interconnect_wrap_3x8.v` | 3-master × 8-slave interconnect; address map for all SoC peripherals |
| `sw/start.S` | MRAC CSR 0x7C0 initialisation: `li t0, 0x00000002; csrw 0x7C0, t0` |
| `sw/src/test_harness.c` | 36 test cases with THRE polling loop fixes, timer compare fix, data RAM boundary fix |
| `sw/include/regs.h` | Complete peripheral register map |
| `sw/include/uart.h` | `uart_putc` / `uart_puts` / `uart_getc` |
| `sw/Makefile` | Build rules for RV32IMC firmware |

## 5. Completed Address‑Map Audit

The full SoC memory map and peripheral register audit have been completed.  The results are documented in:
- [SoC_Final_Address_Map.xlsx](docs/SoC_Final_Address_Map.xlsx)
- [SoC_Final_Address_Map_Audit.md](docs/SoC_Final_Address_Map_Audit.md)

**Key findings**
- All eight peripheral address windows (M00‑M07) are correctly decoded and match `regs.h`.
- GPIO register offsets were corrected (see `regs.h`).
- Timer `CTRL` reset value is `0x2` as expected.
- **Outstanding issues**
  - **Reset‑vector mismatch** – VeeR core default `0x8000_0000` vs. `soc_top` default `0x0`.  We are keeping `RESET_VEC = 0x0` for now because the linker script places the firmware at `0x0` and the instruction RAM is mapped there.  No RTL change is made; the discrepancy is noted for future boot‑loader integration.
  - **UART THRE stall** – probe data still needed to determine why `LSR[5]` remains low.

**Reserved address space**
- The region `0x0002_6000‑0x0002_FFFF` is currently unmapped; it is documented as reserved for future peripherals.

## Compilation & Simulation Attempt (2026‑11‑07)

- **Environment**: `VCS_HOME`, `PATH`, `SNPSLMD_LICENSE_FILE`, `LM_LICENSE_FILE` set correctly (license reachable at `27021@14.139.1.126`).
- **Compile command** executed (see logs).
- **Result**: **Failed** – missing source file `$RV_ROOT/design/lib/el2_assert.sv`.
  - Error output: `Source file cannot be opened "$RV_ROOT/design/lib/el2_assert.sv"`.
- **Impact**: No simulation binary produced; probe values unavailable.
- **Next action**: Define environment variable `RV_ROOT` to the VeeR EL2 root directory (e.g., `export RV_ROOT=/home/student/Documents/HONOURS_316/316/soc_project_packet_buffering/rtl/RISC-V-VeeR-EL2`). Then re‑run the compile.

*No RTL or firmware modifications were performed.*