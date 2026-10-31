/*
 * ============================================================================
 * File: gpio_defines.vh
 * Project: Reliable Data Transport System SoC
 * Description: Register Map and Bitfield Definitions for GPIO IP
 * Interconnect Slot: M04
 * Base Address: 0x0002_2000  (Window: 0x0002_2000 - 0x0002_2FFF, 4KB)
 * ============================================================================
 */

`ifndef GPIO_DEFINES_VH
`define GPIO_DEFINES_VH

// Base Address in System Interconnect
`define GPIO_BASE_ADDR          32'h0002_2000

// Register Offsets (local 32-bit word aligned)
`define GPIO_REG_DATA_IN        8'h00   // Read Input Pins (RO)
`define GPIO_REG_DATA_OUT       8'h04   // Output Data Register (RW)
`define GPIO_REG_DIR            8'h08   // Direction Register: 1=Output, 0=Input (RW)
`define GPIO_REG_SET            8'h0C   // Atomic Output Bit Set (WO)
`define GPIO_REG_CLEAR          8'h10   // Atomic Output Bit Clear (WO)
`define GPIO_REG_INT_EN         8'h14   // Interrupt Enable per pin (RW)
`define GPIO_REG_INT_TYPE       8'h18   // Interrupt Type: 0=Edge, 1=Level (RW)
`define GPIO_REG_INT_POL        8'h1C   // Interrupt Polarity: 0=Rising/High, 1=Falling/Low (RW)
`define GPIO_REG_INT_STATUS     8'h20   // Interrupt Pending Status (RW / W1C)

`endif // GPIO_DEFINES_VH
