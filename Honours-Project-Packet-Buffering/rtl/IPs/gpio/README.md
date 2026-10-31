# GPIO IP Core — RISC-V VeeR EL2 SoC Packet Buffering

## 1. Overview
The GPIO IP Core provides 32-bit configurable General Purpose Digital Input/Output capabilities, atomic bit manipulation, dual-stage CDC input synchronization, edge and level event interrupt detection, and PIC interrupt signaling for the RISC-V VeeR EL2 SoC.

- **Interconnect Slot:** M04
- **Base Address:** `0x0002_2000` (Window: `0x0002_2000` - `0x0002_2FFF`, 4KB)
- **Bus Protocols:** AXI4 full subordinate (`gpio_top.v`) and AXI4-Lite (`gpio_axi4lite.v`)
- **Clock Domain:** `clk` (Synchronous with AXI interconnect)

## 2. Register Map

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `GPIO_REG_DATA_IN` | RO | `0x00000000` | Synchronized external physical inputs (`gpio_i`). |
| `0x04` | `GPIO_REG_DATA_OUT` | RW | `0x00000000` | Output pin driver levels (`gpio_o`). |
| `0x08` | `GPIO_REG_DIR` | RW | `0x00000000` | Direction register: 1=Output, 0=Input (`gpio_oe`). Default all inputs. |
| `0x0C` | `GPIO_REG_SET` | WO | `0x00000000` | Atomic bit-set for `GPIO_REG_DATA_OUT`. Write 1 to set bit. |
| `0x10` | `GPIO_REG_CLEAR` | WO | `0x00000000` | Atomic bit-clear for `GPIO_REG_DATA_OUT`. Write 1 to clear bit. |
| `0x14` | `GPIO_REG_INT_EN` | RW | `0x00000000` | Per-pin interrupt enable mask. |
| `0x18` | `GPIO_REG_INT_TYPE` | RW | `0x00000000` | 0 = Edge-triggered, 1 = Level-triggered. |
| `0x1C` | `GPIO_REG_INT_POL` | RW | `0x00000000` | 0 = Rising-edge / Active-high, 1 = Falling-edge / Active-low. |
| `0x20` | `GPIO_REG_INT_STATUS` | RW / W1C | `0x00000000` | Interrupt pending status. Clear by writing 1 (W1C). |

## 3. Hardware Ports

- **AXI4 Slave:** Standard 32-bit AXI4 interface (`awid`, `awaddr`, `awlen`, `wdata`, `wstrb`, `bid`, `bresp`, `arid`, `araddr`, `rdata`, `rresp`, etc.)
- **Dedicated Physical Signals:**
  - `gpio_i[31:0]`: Physical input signals from external world / board pins
  - `gpio_o[31:0]`: Physical output signals to external world / LEDs
  - `gpio_oe[31:0]`: Output enable controls for external tri-state buffers
  - `gpio_irq_o`: Level interrupt line to VeeR PIC

## 4. Verification
Run `./run_sim.sh` to compile and execute the self-checking testbench (`tb_gpio.v`) with Synopsys VCS.
All tests pass.
