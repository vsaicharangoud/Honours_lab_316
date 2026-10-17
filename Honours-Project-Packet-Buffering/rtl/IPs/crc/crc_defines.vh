/*
 * ============================================================================
 * File: crc_defines.vh
 * Project: Reliable Data Transport System SoC
 * Description: Register definitions, bit masks, and default parameters
 *              for the CRC-32 IP Core (Base Address: 0x000A_0000).
 * ============================================================================
 */

`ifndef CRC_DEFINES_VH
`define CRC_DEFINES_VH

// ----------------------------------------------------------------------------
// Register Address Offsets (Base: 0x000A_0000, 4 KB Allocated Space)
// ----------------------------------------------------------------------------
`define CRC_REG_CTRL            6'h00   // [R/W] Control Register
`define CRC_REG_STATUS          6'h04   // [R/W1C] Status Register
`define CRC_REG_CALC_RESULT     6'h08   // [RO]  Calculated 32-bit CRC Result
`define CRC_REG_EXP_RESULT      6'h0C   // [R/W] Expected 32-bit CRC Result
`define CRC_REG_POLY            6'h10   // [R/W] CRC Polynomial Register
`define CRC_REG_INIT_VAL        6'h14   // [R/W] CRC Initial Value Register
`define CRC_REG_BYTE_COUNT      6'h18   // [RO]  Processed Packet Byte Count
`define CRC_REG_MANUAL_DATA     6'h1C   // [WO]  Direct CPU Data Input Port
`define CRC_REG_ERROR_COUNT     6'h20   // [R/W1C] Cumulative CRC Error Count
`define CRC_REG_PASS_COUNT      6'h24   // [R/W1C] Cumulative CRC Pass Count
`define CRC_REG_MODE_CONFIG     6'h28   // [R/W] Mode and Configuration Register

// ----------------------------------------------------------------------------
// CRC_REG_CTRL [0x00] Bit Definitions
// ----------------------------------------------------------------------------
`define CRC_CTRL_ENABLE_BIT     0       // 1 = Enable CRC Engine, 0 = Disable/Bypass
`define CRC_CTRL_RESET_BIT      1       // 1 = Soft Reset CRC engine state
`define CRC_CTRL_IE_DONE_BIT    2       // 1 = Interrupt Enable on CRC Done
`define CRC_CTRL_IE_ERROR_BIT   3       // 1 = Interrupt Enable on CRC Error
`define CRC_CTRL_AUTO_CLEAR_BIT 4       // 1 = Auto-clear CRC on next packet start

// ----------------------------------------------------------------------------
// CRC_REG_STATUS [0x04] Bit Definitions
// ----------------------------------------------------------------------------
`define CRC_STATUS_BUSY_BIT     0       // 1 = Processing packet data
`define CRC_STATUS_DONE_BIT     1       // 1 = Packet CRC check completed
`define CRC_STATUS_PASS_BIT     2       // 1 = Packet CRC MATCH (Valid packet)
`define CRC_STATUS_ERROR_BIT    3       // 1 = Packet CRC MISMATCH (Corrupted packet)
`define CRC_STATUS_STREAM_ACT_BIT 4     // 1 = Stream interface currently active
`define CRC_STATUS_IRQ_BIT      5       // 1 = Interrupt currently pending

// ----------------------------------------------------------------------------
// CRC_REG_MODE_CONFIG [0x28] Bit Definitions
// ----------------------------------------------------------------------------
// Check Mode:
//   2'b00 = Trailing Mode: Last 4 bytes of packet payload hold received CRC (Ethernet/FCS)
//   2'b01 = Register Mode: Compare against CRC_REG_EXP_RESULT set by CPU
//   2'b10 = Compute-Only Mode: Only compute CRC, do not perform auto-compare
`define CRC_MODE_TRAILING       2'b00
`define CRC_MODE_REGISTER       2'b01
`define CRC_MODE_COMPUTE_ONLY   2'b10

// ----------------------------------------------------------------------------
// Default CRC-32 IEEE 802.3 Parameters
// ----------------------------------------------------------------------------
`define CRC32_DEFAULT_POLY      32'h04C11DB7    // Normal IEEE 802.3 polynomial
`define CRC32_DEFAULT_POLY_REV  32'hEDB88320    // Reflected polynomial (LSB first)
`define CRC32_DEFAULT_INIT      32'hFFFFFFFF    // Standard initial seed
`define CRC32_DEFAULT_XOROUT    32'hFFFFFFFF    // Standard final XOR value

`endif // CRC_DEFINES_VH
