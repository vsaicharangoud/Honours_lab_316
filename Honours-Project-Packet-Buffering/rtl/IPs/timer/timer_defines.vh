/*
 * ============================================================================
 * File: timer_defines.vh
 * Project: Reliable Data Transport System SoC
 * Description: Register Map and Bitfield Definitions for Timer IP
 * Interconnect Slot: M03
 * Base Address: 0x0002_1000  (Window: 0x0002_1000 - 0x0002_1FFF, 4KB)
 * ============================================================================
 */

`ifndef TIMER_DEFINES_VH
`define TIMER_DEFINES_VH

// Base Address in System Interconnect
`define TIMER_BASE_ADDR         32'h0002_1000

// Register Offsets (local 32-bit word aligned)
`define TIMER_REG_CTRL          8'h00   // Timer Control Register (RW)
`define TIMER_REG_STATUS        8'h04   // Timer Status Register (RO / W1C)
`define TIMER_REG_VALUE         8'h08   // Timer Current Counter Value (RW)
`define TIMER_REG_COMPARE       8'h0C   // Timer Compare Register (RW)
`define TIMER_REG_PRESCALER     8'h10   // Timer Clock Prescaler Divisor (RW)

// Control Register Bitfields (TIMER_REG_CTRL)
`define TIMER_CTRL_EN_BIT       0       // 1: Timer enabled / running
`define TIMER_CTRL_RELOAD_BIT   1       // 1: Periodic (auto-reload to 0 on match), 0: One-shot
`define TIMER_CTRL_RST_BIT      2       // 1: Reset counter to 0 (auto-clears)
`define TIMER_CTRL_IE_BIT       3       // 1: Match interrupt enable
`define TIMER_CTRL_PWM_BIT      4       // 1: Enable PWM output pin

// Status Register Bitfields (TIMER_REG_STATUS)
`define TIMER_STAT_RUNNING_BIT  0       // 1: Timer is currently running
`define TIMER_STAT_MATCH_BIT    1       // 1: Compare match occurred (W1C)
`define TIMER_STAT_OVF_BIT      2       // 1: 32-bit counter overflow occurred (W1C)

`endif // TIMER_DEFINES_VH
