# SoC Final Address Map Audit

**Project:** RISC-V VeeR EL2 SoC Packet Buffering
**Date:** 2026-11-07

## 1. Handover Summary
- The repository compiles cleanly after Kiro's last session.
- Firmware loads and runs until it stalls on UART THRE polling (see `soc_status_and_progress.txt`).
- Debug probes were added to `tb/tb_soc_top.sv` to capture UART read data and internal THRE signals.
- Known issues from Kiro:
  - Reset‑vector discrepancy: VeeR core uses `RV_RESET_VEC = 0x8000_0000` while `soc_top.v` defaults `RESET_VEC = 0x0`.
  - GPIO register offsets were mismatched (fixed in `regs.h`).
  - UART THRE loop still hangs – needs probe confirmation.
  - AXI interconnect master‑access masks were corrected to `3'b111`.

## 2. Verification Methodology
| Step | Artifact / Source | Action |
|------|-------------------|--------|
| 2.1 | `rtl/soc_top.v` (lines 33‑34) | Checked `RESET_VEC` parameter default.
| 2.2 | VeeR EL2 core (`veer_cpu_subsystem.sv`) | Confirmed reset vector is supplied via `rst_vec` input (31‑bit). Default value is defined by the core configuration (`RV_RESET_VEC`).
| 2.3 | `rtl/interconnect/axi_interconnect_wrap_3x8.v` (lines 18‑25) | Verified address map for all eight slaves.
| 2.4 | `sw/include/regs.h` | Cross‑checked base addresses and register offsets.
| 2.5 | Simulation log `sim_soc_top.log` (lines 124‑131) | Confirmed that LSU reads/writes hit the expected address windows.
| 2.6 | UART RTL (`axi_uart_top.v`, `axi_uart.vh`) | Mapped register offsets and THRE logic.
| 2.7 | Timer RTL (`timer_top.v`) | Checked control register offsets and default reset value (`CTRL` = `0x2`).
| 2.8 | GPIO RTL (`gpio_top.v`) | Confirmed register layout matches the corrected `regs.h`.
| 2.9 | FIFO, CRC, Packet Counter RTL | Verified base addresses and simple register maps.

## 3. Findings
### 3.1 Reset Vector
- **RTL (soc_top.v):** `parameter [31:0] RESET_VEC = 32'h0000_0000;`
- **VeeR EL2 core:** Exposes `rst_vec[31:1]` input; default value in the core snapshot is `RV_RESET_VEC = 0x8000_0000`.
- **Firmware/linker:** Starts at `0x0000_0000` (see `linker.ld`). 
- **Status:** **NEEDS REVIEW** – the SoC does not currently forward the VeeR reset vector. Either the `RESET_VEC` parameter must be overridden to `0x8000_0000` or the core must be re‑configured to use `0x0`.

### 3.2 Instruction / Data Memory
- **Base addresses:** `0x0000_0000` – `0x0000_FFFF` (Instr), `0x0001_0000` – `0x0001_FFFF` (Data).
- **Size:** 64 KB each, matches the interconnect address windows and simulation log.
- **Verification:** Confirmed via interconnect mapping and memory initialization (`program.hex`). No overlaps.

### 3.3 UART
- **Base:** `0x0002_0000` – `0x0002_0FFF` (4 KB window).
- **Register offsets (from `regs.h` & RTL):**
  - THR/RHR: `0x00`
  - IER: `0x04`
  - LCR: `0x0C`
  - **LSR:** `0x14`
- **RTL (`axi_uart_top.v`):** LSR bits `THRE` (`_UART_LSR_THRE_` = 5) and `TEMT` (`_UART_LSR_TEMT_` = 6) are driven by `available_write_space_int`.
- **Probe outcome (pending):** Debug probes added in `tb/tb_soc_top.sv` will confirm whether LSR[5] is actually `0` at runtime.
- **Status:** **NEEDS REVIEW** – UART THRE loop still unresolved.

### 3.4 Timer / PWM
- **Base:** `0x0002_1000` – `0x0002_1FFF`.
- **Registers (from `regs.h`):**
  - `CTRL` (0x00) – reset value `0x2` (enable bit set). Confirmed in RTL (`timer_top.v`).
  - `STATUS` (0x04), `VALUE` (0x08), `COMPARE` (0x0C), `PRESCALER` (0x10).
- **Verification:** Address decoding and default `CTRL` value verified via RTL and simulation log.

### 3.5 GPIO
- **Base:** `0x0002_2000` – `0x0002_2FFF`.
- **Registers (corrected):**
  - `DATA_IN` 0x00, `DATA_OUT` 0x04, `DIR` 0x08, `SET` 0x0C, `CLR` 0x10, `INT_EN` 0x14, `INT_TYPE` 0x18, `INT_POL` 0x1C, `INT_STATUS` 0x20.
- **RTL (`gpio_top.v`)** matches these offsets; `regs.h` was updated accordingly (lines 48‑52).
- **Status:** Verified.

### 3.6 Packet FIFO
- **Base:** `0x0002_3000` – `0x0002_3FFF`.
- **Registers:** `CTRL` 0x00, `STATUS` 0x04, `DATA` 0x08.
- **RTL (`packet_fifo_top.v`)** confirms these offsets.
- **Status:** Verified.

### 3.7 CRC‑32 Checker
- **Base:** `0x0002_4000` – `0x0002_4FFF`.
- **Registers:** `CTRL` 0x00, `STATUS` 0x04, `DATA_IN` 0x08, `RESULT` 0x0C.
- **RTL (`crc_top.v`)** matches.
- **Status:** Verified.

### 3.8 Packet Counter
- **Base:** `0x0002_5000` – `0x0002_5FFF`.
- **Registers:** `RECV` 0x00, `PROC` 0x04, `ERR` 0x08.
- **RTL (`packet_counter_axi.v`)** aligns.
- **Status:** Verified.

## 4. Overlap / Reserved Regions
- No overlapping address windows exist in the interconnect configuration.
- The address space from `0x0002_6000` upward is currently unused (potential reserved area for future IPs).
- All slave connections are enabled for all masters (`3'b111`).

## 5. Summary Table (see accompanying Excel)
| Region | Base Addr | End Addr | Size (bytes) | Peripheral | Register Offsets (hex) | Notes |
|--------|-----------|----------|--------------|------------|------------------------|-------|
| Instruction RAM | 0x0000_0000 | 0x0000_FFFF | 65536 | Instruction Memory | N/A | Verified |
| Data RAM | 0x0001_0000 | 0x0001_FFFF | 65536 | Data Memory | N/A | Verified |
| UART | 0x0002_0000 | 0x0002_0FFF | 4096 | UART | THR/RHR 0x00, IER 0x04, LCR 0x0C, LSR 0x14 | **NEEDS REVIEW** – THRE behavior |
| Timer | 0x0002_1000 | 0x0002_1FFF | 4096 | Timer / PWM | CTRL 0x00, STATUS 0x04, VALUE 0x08, COMPARE 0x0C, PRESCALER 0x10 | CTRL reset = 0x2 |
| GPIO | 0x0002_2000 | 0x0002_2FFF | 4096 | GPIO | DATA_IN 0x00, DATA_OUT 0x04, DIR 0x08, SET 0x0C, CLR 0x10, INT_EN 0x14, INT_TYPE 0x18, INT_POL 0x1C, INT_STATUS 0x20 | Offsets corrected |
| FIFO | 0x0002_3000 | 0x0002_3FFF | 4096 | Packet FIFO | CTRL 0x00, STATUS 0x04, DATA 0x08 | Verified |
| CRC | 0x0002_4000 | 0x0002_4FFF | 4096 | CRC‑32 Engine | CTRL 0x00, STATUS 0x04, DATA_IN 0x08, RESULT 0x0C | Verified |
| Packet Counter | 0x0002_5000 | 0x0002_5FFF | 4096 | Packet Counter | RECV 0x00, PROC 0x04, ERR 0x08 | Verified |
| **Core Reset Vector** | **0x8000_0000** (VeeR) | – | – | – | – | **NEEDS REVIEW** – mismatch with `soc_top.v` default |

## 6. Recommendations
1. **Resolve Reset‑Vector Mismatch** – either:
   - Override `RESET_VEC` in `soc_top.v` to `0x8000_0000` (parameter override), **or**
   - Configure the VeeR core snapshot to use `0x0` as `RV_RESET_VEC` to match current firmware.
2. **Run UART Debug Probes** – collect `DBG-UART-RD` and `DBG-UART-INT` output to confirm THRE value. If THRE is stuck at `0`, investigate the `available_write_space_int` generation (possible generate‑case issue).
3. **Add Documentation** – update `docs/SOC_PROJECT_CURRENT_STATUS.md` with the audit results and flagged items.
4. **Future IP Slots** – reserve address range `0x0002_6000‑0x0002_FFFF` for additional peripherals.

---
*All source‑line references are included in the Excel file (see columns `RTL Ref` and `Firmware Ref`).*
