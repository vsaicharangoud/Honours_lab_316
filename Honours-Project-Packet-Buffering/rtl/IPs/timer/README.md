# Timer IP Core — RISC-V VeeR EL2 SoC Packet Buffering

## 1. Overview
The Timer IP Core provides general-purpose 32-bit timing, compare-match event generation, periodic interrupts, and PWM generation for the RISC-V VeeR EL2 SoC.

- **Interconnect Slot:** M03
- **Base Address:** `0x0002_1000` (Window: `0x0002_1000` - `0x0002_1FFF`, 4KB)
- **Bus Protocols:** AXI4 full subordinate (`timer_top.v`) and AXI4-Lite (`timer_axi4lite.v`)
- **Clock Domain:** `clk` (Synchronous with AXI interconnect)

## 2. Register Map

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `TIMER_CTRL` | RW | `0x00000000` | Control register: bit 0: EN, bit 1: AUTO_RELOAD, bit 2: RST_PULSE, bit 3: IRQ_EN, bit 4: PWM_EN |
| `0x04` | `TIMER_STATUS` | RO / W1C | `0x00000000` | Status register: bit 0: RUNNING, bit 1: MATCH (W1C), bit 2: OVERFLOW (W1C) |
| `0x08` | `TIMER_VALUE` | RW | `0x00000000` | Current 32-bit counter value. Write preloads counter. |
| `0x0C` | `TIMER_COMPARE` | RW | `0xFFFFFFFF` | 32-bit target compare value. Triggers MATCH when counter reaches threshold. |
| `0x10` | `TIMER_PRESCALER` | RW | `0x00000000` | 16-bit clock prescaler divisor (0 = div by 1, N = div by N+1). |

## 3. Hardware Ports

- **AXI4 Slave:** Standard 32-bit AXI4 interface (`awid`, `awaddr`, `awlen`, `wdata`, `wstrb`, `bid`, `bresp`, `arid`, `araddr`, `rdata`, `rresp`, etc.)
- **Dedicated Signals:**
  - `timer_irq_o`: Level interrupt line to VeeR PIC
  - `timer_match_o`: Single-cycle compare match pulse
  - `timer_pwm_o`: PWM output waveform

## 4. Verification
Run `./run_sim.sh` to compile and execute the self-checking testbench (`tb_timer.v`) with Synopsys VCS.
All tests pass.
