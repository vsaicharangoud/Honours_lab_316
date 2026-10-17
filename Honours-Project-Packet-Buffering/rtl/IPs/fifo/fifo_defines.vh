/*
 * ============================================================================
 * File: fifo_defines.vh
 * Project: Reliable Data Transport System SoC
 * Description: Register definitions, bit masks, and parameters for the
 *              Packet FIFO IP Core (Base Address: 0x0007_0000, 4 KB Space).
 * ============================================================================
 */

`ifndef FIFO_DEFINES_VH
`define FIFO_DEFINES_VH

// ----------------------------------------------------------------------------
// Register Address Offsets (Base: 0x0007_0000, 4 KB Allocated Space)
// ----------------------------------------------------------------------------
`define FIFO_REG_DATA            6'h00   // [R/W] Data Port (Pop on Read, Push on Write with tlast=0)
`define FIFO_REG_DATA_LAST       6'h04   // [WO]  Data Port (Push on Write with tlast=1)
`define FIFO_REG_STATUS          6'h08   // [RO]  Status Register (Full, Empty, Overflow, IRQ)
`define FIFO_REG_CTRL            6'h0C   // [R/W] Control Register (Enable, Stream Mode, IRQ En)
`define FIFO_REG_DIAG_STATUS     6'h10   // [R/W1C] CDC Diagnostic & Fault Status Register
`define FIFO_REG_OCCUPANCY       6'h14   // [RO]  FIFO Occupancy (Read and Write domain levels)
`define FIFO_REG_THRESHOLD       6'h18   // [R/W] Almost-Full / Almost-Empty Thresholds
`define FIFO_REG_PACKET_COUNT    6'h1C   // [RO]  Cumulative Completed Packets Count

// ----------------------------------------------------------------------------
// FIFO_REG_STATUS [0x08] Bit Definitions
// ----------------------------------------------------------------------------
`define FIFO_STATUS_WR_FULL_BIT        0   // 1 = FIFO Full (Write domain)
`define FIFO_STATUS_RD_EMPTY_BIT       1   // 1 = FIFO Empty (Read domain)
`define FIFO_STATUS_WR_OVERFLOW_BIT    2   // 1 = Write attempted while full
`define FIFO_STATUS_RD_UNDERFLOW_BIT   3   // 1 = Read attempted while empty
`define FIFO_STATUS_ALMOST_FULL_BIT    4   // 1 = Occupancy >= almost_full_thresh
`define FIFO_STATUS_ALMOST_EMPTY_BIT   5   // 1 = Occupancy <= almost_empty_thresh
`define FIFO_STATUS_STREAM_ACT_BIT     6   // 1 = Downstream streaming active
`define FIFO_STATUS_IRQ_BIT            7   // 1 = Interrupt request active

// ----------------------------------------------------------------------------
// FIFO_REG_CTRL [0x0C] Bit Definitions
// ----------------------------------------------------------------------------
`define FIFO_CTRL_ENABLE_BIT           0   // 1 = IP Enable, 0 = Standby/Disabled
`define FIFO_CTRL_SOFT_RESET_BIT       1   // 1 = Soft Reset pulse
`define FIFO_CTRL_STREAM_EN_BIT        2   // 1 = Auto-stream to CRC engine, 0 = Manual CPU pop
`define FIFO_CTRL_IE_OVERFLOW_BIT      3   // 1 = Interrupt Enable on Overflow
`define FIFO_CTRL_IE_UNDERFLOW_BIT     4   // 1 = Interrupt Enable on Underflow
`define FIFO_CTRL_IE_CDC_ERROR_BIT     5   // 1 = Interrupt Enable on CDC Faults
`define FIFO_CTRL_IE_ALMOST_FULL_BIT   6   // 1 = Interrupt Enable on Almost Full
`define FIFO_CTRL_IE_DATA_AVAIL_BIT    7   // 1 = Interrupt Enable on Data Available

// ----------------------------------------------------------------------------
// FIFO_REG_DIAG_STATUS [0x10] Bit Definitions (Self-Diagnosis & Fault Flags)
// ----------------------------------------------------------------------------
`define FIFO_DIAG_WR_GRAY_ERR_BIT      0   // 1 = Multi-bit Gray code jump in Write domain
`define FIFO_DIAG_RD_GRAY_ERR_BIT      1   // 1 = Multi-bit Gray code jump in Read domain
`define FIFO_DIAG_WR_OVF_STICKY_BIT    2   // 1 = Latched sticky overflow error
`define FIFO_DIAG_RD_UNF_STICKY_BIT    3   // 1 = Latched sticky underflow error
`define FIFO_DIAG_WR_STUCK_BIT         4   // 1 = Write pointer stuck during active writes
`define FIFO_DIAG_RD_STUCK_BIT         5   // 1 = Read pointer stuck during active reads

// ----------------------------------------------------------------------------
// Default Configuration Values
// ----------------------------------------------------------------------------
`define FIFO_DEFAULT_DEPTH             16
`define FIFO_DEFAULT_SYNC_STAGES       2
`define FIFO_DEFAULT_CTRL              32'h0000_0005 // Enable=1, Stream_En=1

`endif // FIFO_DEFINES_VH
