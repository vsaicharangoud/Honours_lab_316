#!/usr/bin/env python3
"""
Generate Phase 1 SoC Honours Project Excel Report
Sheets:
  1. IP_Inventory
  2. SoC_Address_Map
  3. Register_Map
  4. Reserved_Address_Space
  5. Duplicate_IP_Analysis
  6. Adapters_Wrappers
  7. VeeR_EL2_Interface
  8. Integration_Architecture
"""

from openpyxl import Workbook
from openpyxl.styles import (
    PatternFill, Font, Alignment, Border, Side, GradientFill
)
from openpyxl.utils import get_column_letter

# ── Colour palette ──────────────────────────────────────────────────────────
HDR_DARK   = "1F3864"   # deep navy  – sheet headers
HDR_MID    = "2E74B5"   # mid-blue   – section sub-headers
HDR_LIGHT  = "BDD7EE"   # pale blue  – table column headers
ROW_ALT    = "EBF3FB"   # very pale blue – alternate rows
ROW_WHITE  = "FFFFFF"
WARN_AMBER = "FFE699"   # amber      – missing / TBD cells
OK_GREEN   = "E2EFDA"   # light green – confirmed / identical
BOLD_FONT  = Font(bold=True)

def _hdr_font(white=False, sz=11):
    return Font(bold=True, color="FFFFFF" if white else "000000", size=sz)

def _fill(hex_color):
    return PatternFill("solid", fgColor=hex_color)

def _thin_border():
    s = Side(border_style="thin", color="AAAAAA")
    return Border(left=s, right=s, top=s, bottom=s)

def _center():
    return Alignment(horizontal="center", vertical="center", wrap_text=True)

def _left():
    return Alignment(horizontal="left", vertical="center", wrap_text=True)

def set_col_widths(ws, widths):
    for col_idx, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(col_idx)].width = w

def write_title(ws, title, ncols, row=1):
    ws.row_dimensions[row].height = 28
    cell = ws.cell(row=row, column=1, value=title)
    cell.font  = Font(bold=True, size=14, color="FFFFFF")
    cell.fill  = _fill(HDR_DARK)
    cell.alignment = _center()
    ws.merge_cells(start_row=row, start_column=1,
                   end_row=row,   end_column=ncols)

def write_col_headers(ws, headers, row, fill_color=HDR_LIGHT):
    ws.row_dimensions[row].height = 20
    for col, h in enumerate(headers, start=1):
        c = ws.cell(row=row, column=col, value=h)
        c.font      = Font(bold=True, size=10)
        c.fill      = _fill(fill_color)
        c.alignment = _center()
        c.border    = _thin_border()

def write_row(ws, row_idx, values, alt=False, fills=None):
    bg = ROW_ALT if alt else ROW_WHITE
    for col, v in enumerate(values, start=1):
        c = ws.cell(row=row_idx, column=col, value=v)
        f = fills[col-1] if (fills and fills[col-1]) else bg
        c.fill      = _fill(f)
        c.alignment = _left()
        c.border    = _thin_border()
        c.font      = Font(size=10)

def write_section_header(ws, row, text, ncols, color=HDR_MID):
    ws.row_dimensions[row].height = 16
    c = ws.cell(row=row, column=1, value=text)
    c.font      = Font(bold=True, size=10, color="FFFFFF")
    c.fill      = _fill(color)
    c.alignment = _left()
    ws.merge_cells(start_row=row, start_column=1,
                   end_row=row,   end_column=ncols)

# ────────────────────────────────────────────────────────────────────────────
#  SHEET 1 – IP INVENTORY
# ────────────────────────────────────────────────────────────────────────────
def sheet_ip_inventory(wb):
    ws = wb.create_sheet("IP_Inventory")
    NCOLS = 8
    headers = [
        "IP Name", "Source / Location", "Data Width",
        "Bus Interface", "Addr Width (bits)",
        "Registers Available (from RTL)", "Interrupt Output", "Notes"
    ]
    col_w = [22, 38, 14, 22, 18, 42, 16, 44]

    write_title(ws, "SoC Honours Project – IP Inventory (Phase 1)", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    # ── Section: IPs with confirmed RTL ────────────────────────────────────
    write_section_header(ws, 3,
        "IPs WITH CONFIRMED RTL IN REPOSITORY", NCOLS, HDR_MID)

    confirmed = [
        # name, source, dw, iface, aw, regs, irq, notes
        [
            "UART",
            "soc_project_packet_buffering/rtl/UART_IP/src/rtl/\n"
            "Honours_lab_316/axi-lite_uart-ipcore/src/rtl/\n"
            "IPs/axi-lite_uart-ipcore-develop/src/rtl/",
            "32-bit",
            "AXI4-Lite (slave)\n(ID field present – quasi-Lite)",
            "5",
            "RBR/THR @0x00, IER @0x04,\nBAUD_DIV @0x08, LCR @0x0C,\nLSR @0x14\n(6 logical registers)",
            "YES – read_interrupt_o",
            "Three copies in repo – all byte-for-byte IDENTICAL "
            "(confirmed with diff). Single integration slot required. "
            "Has two clock domains (fixed_clk_i + axi_aclk_i). "
            "AXI4→Lite adapter already exists in repo."
        ],
        [
            "SPI",
            "axi-lite_spi-ipcore-develop/src/rtl/",
            "32-bit",
            "AXI4-Lite (slave)\n(ID field present)",
            "7",
            "GIER@0x1C, ISR@0x20, IER@0x28,\nSRR@0x40, CR@0x60, SR@0x64,\n"
            "DTR@0x68, DRR@0x6C, SSR@0x70,\nTFOR@0x74, RFOR@0x78,\n"
            "RCLK@0x30 (custom)\n(12 registers; highest offset 0x78)",
            "Pending – IER/ISR present,\noutput pin NOT yet confirmed",
            "Has two clock domains (fixed_clk_i + axi_aclk_i). "
            "Highest register offset 0x78 → needs ≥128 B address space."
        ],
        [
            "I2C",
            "IPs/i2c-master/rtl/verilog/\n"
            "Honours_lab_316/I2C/rtl/verilog/",
            "8-bit",
            "Wishbone rev-B2 (slave)",
            "3",
            "PRER_LO @0x00 (8b), PRER_HI @0x01,\nCTR @0x02, RXR/TXR @0x03,\n"
            "SR/CR @0x04, (debug:TXR@0x05,\nCR@0x06), SLADR @0x07\n"
            "(8 registers × 8-bit)",
            "YES – wb_inta_o",
            "Wishbone protocol – CANNOT connect directly to AXI interconnect. "
            "Requires AXI4-Lite→Wishbone bridge wrapper. "
            "Both copies are byte-for-byte identical (same codebase)."
        ],
        [
            "AES",
            "Honours_lab_316/aes_core-master/rtl/verilog/\n"
            "IPs/aes_core-master/rtl/verilog/\n"
            "Honours_lab_316/AES-IP/aes_core-master/rtl/verilog/",
            "32-bit",
            "AXI4 full (slave)\naxi_aes_slave.v wrapper",
            "32",
            "CONTROL @0x0000, STATUS @0x0004,\n"
            "KEY0–KEY3 @0x0010–0x001C,\n"
            "TEXT_IN0–3 @0x0020–0x002C,\n"
            "TEXT_OUT0–3 @0x0030–0x003C\n"
            "(11 registers, highest offset 0x3C)",
            "NOT DETERMINED from available RTL\n(no irq output found in axi_aes_slave.v)",
            "Three copies in repo – same source codebase. "
            "AXI4 full interface (not Lite) – direct connection to 32-bit "
            "AXI interconnect is possible. "
            "reset (rst) is ACTIVE-LOW on aes_cipher_top."
        ],
        [
            "PWM",
            "AXI4-Lite-PWM-Controller-IP-Zynq-PYNQ--main/",
            "32-bit",
            "AXI4-Lite (slave)\n(Xilinx auto-generated style – no ID)",
            "4",
            "slv_reg0 @0x00, slv_reg1 @0x04,\nslv_reg2 @0x08, slv_reg3 @0x0C\n"
            "(4 registers × 32-bit)\nOutput: PWM_OUT",
            "None found in RTL",
            "4-bit address bus → 16-byte space. "
            "Xilinx Vivado IP packager style. "
            "No AXI ID signals (pure AXI4-Lite). "
            "Register function (period/duty/etc.) NOT DOCUMENTED in available RTL."
        ],
    ]

    r = 4
    for i, row in enumerate(confirmed):
        fills = None
        write_row(ws, r, row, alt=(i % 2 == 1), fills=fills)
        ws.row_dimensions[r].height = 72
        r += 1

    # ── Section: IPs referenced but NO RTL found ───────────────────────────
    write_section_header(ws, r,
        "IPs REFERENCED IN PROJECT BUT NO RTL FOUND IN REPOSITORY", NCOLS, "C00000")
    r += 1

    missing = [
        ["Instruction Memory", "Referenced in axi_interconnect_wrap_1x8.v comments",
         "NOT DETERMINED", "AXI4 (inferred from interconnect)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "N/A", "RTL not found. Placeholder @ 0x0000_0000 in existing interconnect."],
        ["Data Memory", "Referenced in axi_interconnect_wrap_1x8.v comments",
         "NOT DETERMINED", "AXI4 (inferred from interconnect)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "N/A", "RTL not found. Placeholder @ 0x0001_0000 in existing interconnect."],
        ["Timer", "Referenced in axi_interconnect_wrap comments",
         "NOT DETERMINED", "AXI4 (inferred)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x0004_0000 in full SoC map."],
        ["GPIO", "Referenced in axi_interconnect_wrap comments",
         "NOT DETERMINED", "AXI4 (inferred)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x0005_0000 in full SoC map."],
        ["FIFO (Packet FIFO)", "Referenced in axi_interconnect_wrap comments",
         "NOT DETERMINED", "AXI4 (inferred)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x0006_0000 in full SoC map."],
        ["Packet Counter", "Referenced in axi_interconnect_wrap comments",
         "NOT DETERMINED", "AXI4 (inferred)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x0007_0000 in full SoC map."],
        ["Enhanced Timer", "Referenced in prompt (team member IP)",
         "NOT DETERMINED", "NOT DETERMINED",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x0008_0000."],
        ["CRC", "Referenced in axi_interconnect_wrap comments",
         "NOT DETERMINED", "AXI4 (inferred)",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x0009_0000."],
        ["DMA", "Referenced in prompt (team member IP)",
         "NOT DETERMINED", "NOT DETERMINED",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x000A_0000."],
        ["Interrupt Controller", "Referenced in prompt (team member IP)",
         "NOT DETERMINED", "NOT DETERMINED",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x000B_0000."],
        ["RLE", "Referenced in prompt (team member IP)",
         "NOT DETERMINED", "NOT DETERMINED",
         "NOT DETERMINED", "REGISTER MAP: TO BE DETERMINED FROM IP RTL / SPECIFICATION",
         "NOT DETERMINED", "No RTL found. Slot reserved at 0x000C_0000."],
    ]

    for i, row in enumerate(missing):
        fills = [WARN_AMBER if v == "NOT DETERMINED" else None for v in row]
        write_row(ws, r, row, alt=(i % 2 == 1), fills=fills)
        ws.row_dimensions[r].height = 48
        r += 1

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 2 – SOC ADDRESS MAP
# ────────────────────────────────────────────────────────────────────────────
def sheet_address_map(wb):
    ws = wb.create_sheet("SoC_Address_Map")
    NCOLS = 9
    headers = [
        "IP / Region", "Base Address", "End Address",
        "Allocated Size", "Current Register Usage",
        "Expansion Space", "Data Width",
        "Required Adapter / Wrapper", "Notes"
    ]
    col_w = [24, 15, 15, 14, 30, 16, 13, 34, 42]
    write_title(ws, "SoC Honours Project – Full Memory Map (Phase 1 Draft)", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    rows = [
        # ── VeeR internal regions ──
        ("── VeeR EL2 Internal Memory Regions ──", None, None, None, None, None, None, None, None),
        ("VeeR DCCM\n(Data-Closely-Coupled Memory)",
         "0xF004_0000", "0xF004_FFFF", "64 KB",
         "Internal VeeR DCCM\n(not accessible via LSU AXI)",
         "0 (fixed by VeeR config)", "64-bit internal",
         "None – internal to VeeR core",
         "Region 0xF, offset 0x40000. Configured in veer.config. "
         "NOT memory-mapped through the SoC AXI interconnect."),
        ("VeeR ICCM\n(Instruction-Closely-Coupled Memory)",
         "0xEE00_0000", "0xEE00_FFFF", "64 KB",
         "Internal VeeR ICCM\n(not accessible via IFU AXI)",
         "0 (fixed by VeeR config)", "64-bit internal",
         "None – internal to VeeR core",
         "Region 0xE, top-aligned. Configured in veer.config. "
         "NOT memory-mapped through the SoC AXI interconnect."),
        ("VeeR PIC\n(Programmable Interrupt Controller)",
         "0xF00C_0000", "0xF00C_7FFF", "32 KB",
         "VeeR internal PIC registers\n(memory-mapped inside VeeR)",
         "0 (fixed by VeeR config)", "32-bit (VeeR internal)",
         "None – internal to VeeR core",
         "Region 0xF, offset 0xC0000. "
         "CPU accesses via load/store to this range. "
         "Must NOT be allocated to any SoC peripheral."),

        # ── SoC peripheral region ──
        ("── SoC Peripheral Region ──", None, None, None, None, None, None, None, None),
        ("Instruction Memory",
         "0x0000_0000", "0x0000_FFFF", "64 KB",
         "TO BE DETERMINED FROM IP RTL", "Expansion to 64 KB total",
         "32-bit", "None (if 32-bit AXI memory)",
         "Boot / program memory. reset_vec = 0x8000_0000 (overridable). "
         "IFU AXI fetches from here. RTL not yet provided."),
        ("Data Memory",
         "0x0001_0000", "0x0001_FFFF", "64 KB",
         "TO BE DETERMINED FROM IP RTL", "Expansion to 64 KB total",
         "32-bit", "AXI64→AXI32 adapter on LSU path",
         "General SRAM data storage. RTL not yet provided."),
        ("UART",
         "0x0002_0000", "0x0002_0FFF", "4 KB",
         "6 regs: RBR/THR@+0x00, IER@+0x04,\n"
         "BAUD_DIV@+0x08, LCR@+0x0C, LSR@+0x14\n(28 bytes used)",
         "4 KB − 28 B = ~4068 B free", "32-bit",
         "AXI64→AXI32 adapter (LSU path)\n"
         "+ AXI4→AXI4Lite bridge\n(already exists in repo)",
         "Existing adapter: axi4_to_axi4lite_uart_adapter.v. "
         "UART has 5-bit internal address bus."),
        ("Timer",
         "0x0004_0000", "0x0004_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot. "
         "Note: moved from 0x0002_1000 to give full 4 KB alignment."),
        ("GPIO",
         "0x0005_0000", "0x0005_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot."),
        ("Packet FIFO",
         "0x0006_0000", "0x0006_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot."),
        ("Packet Counter",
         "0x0007_0000", "0x0007_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot."),
        ("Enhanced Timer",
         "0x0008_0000", "0x0008_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot."),
        ("CRC",
         "0x0009_0000", "0x0009_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot."),
        ("DMA",
         "0x000A_0000", "0x000A_FFFF", "64 KB",
         "TO BE DETERMINED FROM IP RTL", "64 KB total",
         "NOT DETERMINED", "TBD – DMA may need 64-bit path",
         "No RTL found. Larger region allocated – DMA typically has "
         "more registers (src/dst/len/control/status per channel)."),
        ("Interrupt Controller",
         "0x000B_0000", "0x000B_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot. "
         "Note: VeeR has internal PIC; this slot is for an external "
         "interrupt controller IP if provided by a team member."),
        ("RLE",
         "0x000C_0000", "0x000C_0FFF", "4 KB",
         "TO BE DETERMINED FROM IP RTL", "~4 KB free",
         "NOT DETERMINED", "TBD – depends on IP interface",
         "No RTL found. Reserved slot."),
        ("SPI",
         "0x000D_0000", "0x000D_0FFF", "4 KB",
         "12 regs: highest offset 0x78 (RFOR)\n(124 bytes used)",
         "4 KB − 124 B = ~3972 B free", "32-bit",
         "AXI64→AXI32 adapter (LSU path)\n"
         "+ AXI4→AXI4Lite bridge (to be created)",
         "SPI has 7-bit internal address bus (128-byte space). "
         "4 KB region provides ample expansion."),
        ("I2C",
         "0x000E_0000", "0x000E_0FFF", "4 KB",
         "8 regs × 8-bit: PRER_LO@+0, PRER_HI@+1,\n"
         "CTR@+2, RXR/TXR@+3, SR/CR@+4,\n(debug@+5,+6), SLADR@+7",
         "4 KB − 8 B = ~4088 B free", "8-bit (Wishbone)",
         "AXI64→AXI32 adapter (LSU path)\n"
         "+ AXI4-Lite→Wishbone bridge (to be created)",
         "I2C is Wishbone. Requires a bridge wrapper. "
         "8-bit data width mismatch with 32-bit AXI must be handled "
         "in the bridge wrapper."),
        ("AES",
         "0x000F_0000", "0x000F_0FFF", "4 KB",
         "11 regs: CTRL@+0x00, STAT@+0x04,\n"
         "KEY0–3@+0x10–0x1C, TXT_IN0–3@+0x20–0x2C,\n"
         "TXT_OUT0–3@+0x30–0x3C\n(64 bytes used)",
         "4 KB − 64 B = ~4032 B free", "32-bit",
         "AXI64→AXI32 adapter (LSU path)\n"
         "(AES uses AXI4 full – no Lite bridge needed)",
         "AES has AXI4 full slave interface. "
         "reset is ACTIVE-LOW on aes_cipher_top."),
        ("PWM",
         "0x0010_0000", "0x0010_0FFF", "4 KB",
         "4 regs × 32-bit:\nslv_reg0@+0x00, slv_reg1@+0x04,\n"
         "slv_reg2@+0x08, slv_reg3@+0x0C",
         "4 KB − 16 B = ~4080 B free", "32-bit",
         "AXI64→AXI32 adapter (LSU path)\n"
         "+ AXI4→AXI4Lite bridge (no ID in PWM)",
         "PWM has 4-bit internal address bus (pure AXI4-Lite, no ID)."),

        # ── Reserved expansion ──
        ("── Reserved / Future Expansion ──", None, None, None, None, None, None, None, None),
        ("Future IP Expansion Bank A\n(Team member IPs not yet provided)",
         "0x0011_0000", "0x001F_FFFF", "~1 MB",
         "RESERVED", "~1 MB", "TBD",
         "TBD", "Reserved for additional IPs from all 5 team members. "
         "Each team member can be allocated 64–256 KB sub-regions here."),
        ("RESERVED – must not use\n(VeeR PIC region)",
         "0xF00C_0000", "0xF00C_7FFF", "32 KB",
         "VeeR internal PIC only", "0",
         "32-bit VeeR internal", "None",
         "DO NOT allocate to any SoC peripheral. VeeR accesses this "
         "region internally for interrupt management."),
        ("RESERVED – must not use\n(VeeR DCCM region)",
         "0xF004_0000", "0xF004_FFFF", "64 KB",
         "VeeR internal DCCM only", "0",
         "64-bit internal", "None",
         "DO NOT allocate to any SoC peripheral."),
        ("RESERVED – must not use\n(VeeR ICCM region)",
         "0xEE00_0000", "0xEE00_FFFF", "64 KB",
         "VeeR internal ICCM only", "0",
         "64-bit internal", "None",
         "DO NOT allocate to any SoC peripheral."),
    ]

    r = 3
    section_rows = set()
    for i, row in enumerate(rows):
        r += 1
        if row[1] is None:
            # Section divider
            section_rows.add(r)
            ws.row_dimensions[r].height = 14
            c = ws.cell(row=r, column=1, value=row[0])
            c.font      = Font(bold=True, size=10, color="FFFFFF")
            c.fill      = _fill(HDR_MID)
            c.alignment = _left()
            ws.merge_cells(start_row=r, start_column=1,
                           end_row=r,   end_column=NCOLS)
        else:
            alt = (i % 2 == 0)
            fills_row = []
            for v in row:
                if v and ("TO BE DETERMINED" in str(v) or "NOT DETERMINED" in str(v) or
                          "TBD" in str(v) or "RESERVED" == str(v)):
                    fills_row.append(WARN_AMBER)
                elif v and "RESERVED – must not use" in str(v):
                    fills_row.append("FFD7D7")  # light red
                else:
                    fills_row.append(None)
            write_row(ws, r, list(row), alt=alt, fills=fills_row)
            ws.row_dimensions[r].height = 60

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 3 – REGISTER MAP
# ────────────────────────────────────────────────────────────────────────────
def sheet_register_map(wb):
    ws = wb.create_sheet("Register_Map")
    NCOLS = 7
    headers = [
        "IP", "Register Name", "Offset (hex)",
        "Absolute Address (hex)", "Width (bits)", "Access", "Description"
    ]
    col_w = [18, 20, 14, 20, 12, 10, 54]
    write_title(ws, "SoC Honours Project – Register Map (IPs with confirmed RTL)", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    regs = [
        # UART base 0x0002_0000
        ("UART\n(base 0x0002_0000)", "RBR (Rx Buffer Reg)",  "0x00", "0x0002_0000", "32", "R",   "Receive data register. Read to get received byte."),
        ("",                          "THR (Tx Holding Reg)", "0x00", "0x0002_0000", "32", "W",   "Transmit data register. Write to send byte. Same offset as RBR."),
        ("",                          "IER (Interrupt Enable Reg)", "0x04", "0x0002_0004", "32", "R/W", "Interrupt enable control."),
        ("",                          "BAUD_DIVISOR",         "0x08", "0x0002_0008", "32", "R/W", "Baud rate divisor. Active when DLAB=1 in LCR. Default: clk/115200."),
        ("",                          "LCR (Line Control Reg)","0x0C", "0x0002_000C", "32", "R/W",
         "[7]=DLAB, [4]=parity_mode, [3]=parity_en, [2]=stop_bits, [1:0]=word_len"),
        ("",                          "LSR (Line Status Reg)", "0x14", "0x0002_0014", "32", "R",
         "[6]=TEMT (TX empty), [5]=THRE (TX FIFO empty), [0]=data_ready"),

        # SPI base 0x000D_0000
        ("SPI\n(base 0x000D_0000)", "GIER (Global IRQ Enable)", "0x1C", "0x000D_001C", "32", "R/W", "Global interrupt enable register."),
        ("", "ISR (Interrupt Status)",  "0x20", "0x000D_0020", "32", "R/W", "Interrupt status register. Write 1 to clear."),
        ("", "IER (Interrupt Enable)",  "0x28", "0x000D_0028", "32", "R/W", "Interrupt enable register."),
        ("", "RCLK (custom Ratio Clk)", "0x30", "0x000D_0030", "32", "R/W", "Custom SPI clock ratio register. Reset value = 4."),
        ("", "SRR (Soft Reset)",        "0x40", "0x000D_0040", "32", "W",   "Software reset. Write 0x0000_000A to reset."),
        ("", "CR (Control Reg)",        "0x60", "0x000D_0060", "32", "R/W",
         "[9]=LSB_first, [6]=RX_FIFO_rst, [5]=TX_FIFO_rst, [4]=CPHA, [3]=CPOL, [2]=MASTER, [1]=SPI_EN"),
        ("", "SR (Status Reg)",         "0x64", "0x000D_0064", "32", "R",
         "[5]=SMOD_SEL, [4]=MODF, [3]=TX_FULL, [2]=TX_EMPTY, [1]=RX_FULL, [0]=RX_EMPTY"),
        ("", "DTR (Data TX Register)",  "0x68", "0x000D_0068", "32", "W",   "Write byte to TX FIFO."),
        ("", "DRR (Data RX Register)",  "0x6C", "0x000D_006C", "32", "R",   "Read byte from RX FIFO."),
        ("", "SSR (Slave Select)",      "0x70", "0x000D_0070", "32", "R/W", "Chip select (active low bits). Reset = 0xFFFF_FFFF."),
        ("", "TFOR (TX FIFO Occupancy)","0x74", "0x000D_0074", "32", "R",   "TX FIFO occupancy register."),
        ("", "RFOR (RX FIFO Occupancy)","0x78", "0x000D_0078", "32", "R",   "RX FIFO occupancy register."),

        # I2C base 0x000E_0000
        ("I2C / Wishbone\n(base 0x000E_0000)",
         "PRER_LO (Prescale Low)",  "0x00", "0x000E_0000", "8", "R/W", "Clock prescale register [7:0]. Reset = 0xFF."),
        ("", "PRER_HI (Prescale High)", "0x01", "0x000E_0001", "8", "R/W", "Clock prescale register [15:8]. Reset = 0xFF."),
        ("", "CTR (Control Reg)",       "0x02", "0x000E_0002", "8", "R/W", "[7]=EN (core enable), [6]=IEN (interrupt enable)."),
        ("", "TXR/RXR (Data)",          "0x03", "0x000E_0003", "8", "W/R", "Write=TX byte. Read=RX byte."),
        ("", "CR/SR (Cmd/Status)",      "0x04", "0x000E_0004", "8", "W/R",
         "Write=Command: [7]=STA,[6]=STO,[5]=RD,[4]=WR,[3]=ACK,[0]=IACK. "
         "Read=Status: [7]=RxACK,[6]=BUSY,[5]=AL,[1]=TIP,[0]=IF."),
        ("", "SLADR (Slave Addr)",      "0x07", "0x000E_0007", "8", "R/W", "7-bit target slave address [6:0]. Default = 0x7E."),

        # AES base 0x000F_0000
        ("AES\n(base 0x000F_0000)",
         "CONTROL",    "0x0000", "0x000F_0000", "32", "R/W",
         "[0]=START (write 1→1-cycle aes_ld), [1]=CLEAR_DONE, [2]=SOFT_RESET."),
        ("", "STATUS",     "0x0004", "0x000F_0004", "32", "R",
         "[0]=DONE (latched), [1]=BUSY, [2]=KEY_VALID, [3]=INPUT_VALID."),
        ("", "KEY0",       "0x0010", "0x000F_0010", "32", "R/W", "AES key [127:96]."),
        ("", "KEY1",       "0x0014", "0x000F_0014", "32", "R/W", "AES key [95:64]."),
        ("", "KEY2",       "0x0018", "0x000F_0018", "32", "R/W", "AES key [63:32]."),
        ("", "KEY3",       "0x001C", "0x000F_001C", "32", "R/W", "AES key [31:0]."),
        ("", "TEXT_IN0",   "0x0020", "0x000F_0020", "32", "R/W", "Plaintext input [127:96]."),
        ("", "TEXT_IN1",   "0x0024", "0x000F_0024", "32", "R/W", "Plaintext input [95:64]."),
        ("", "TEXT_IN2",   "0x0028", "0x000F_0028", "32", "R/W", "Plaintext input [63:32]."),
        ("", "TEXT_IN3",   "0x002C", "0x000F_002C", "32", "R/W", "Plaintext input [31:0]."),
        ("", "TEXT_OUT0",  "0x0030", "0x000F_0030", "32", "R",   "Ciphertext output [127:96]."),
        ("", "TEXT_OUT1",  "0x0034", "0x000F_0034", "32", "R",   "Ciphertext output [95:64]."),
        ("", "TEXT_OUT2",  "0x0038", "0x000F_0038", "32", "R",   "Ciphertext output [63:32]."),
        ("", "TEXT_OUT3",  "0x003C", "0x000F_003C", "32", "R",   "Ciphertext output [31:0]."),

        # PWM base 0x0010_0000
        ("PWM\n(base 0x0010_0000)",
         "slv_reg0",   "0x00", "0x0010_0000", "32", "R/W",
         "PWM register 0. Exact function NOT DETERMINED from available RTL."),
        ("", "slv_reg1",   "0x04", "0x0010_0004", "32", "R/W",
         "PWM register 1. Exact function NOT DETERMINED from available RTL."),
        ("", "slv_reg2",   "0x08", "0x0010_0008", "32", "R/W",
         "PWM register 2. Exact function NOT DETERMINED from available RTL."),
        ("", "slv_reg3",   "0x0C", "0x0010_000C", "32", "R/W",
         "PWM register 3. Exact function NOT DETERMINED from available RTL."),
    ]

    r = 3
    ip_colors = {
        "UART":  "DDEEFF",
        "SPI":   "E2EFDA",
        "I2C":   "FFF2CC",
        "AES":   "FCE4D6",
        "PWM":   "EAD1DC",
    }
    current_ip = None
    current_color = ROW_WHITE
    alt = False
    for row in regs:
        r += 1
        ip_label = row[0]
        if ip_label:
            for k, v in ip_colors.items():
                if k in ip_label:
                    current_color = v
                    break
            alt = False
        else:
            alt = not alt

        fills = [current_color] * NCOLS
        # Flag TBD cells
        for ci, v in enumerate(row):
            if "NOT DETERMINED" in str(v):
                fills[ci] = WARN_AMBER

        write_row(ws, r, list(row), fills=fills)
        ws.row_dimensions[r].height = 30

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 4 – RESERVED ADDRESS SPACE
# ────────────────────────────────────────────────────────────────────────────
def sheet_reserved(wb):
    ws = wb.create_sheet("Reserved_Address_Space")
    NCOLS = 5
    headers = ["Region", "Base Address", "End Address", "Size", "Reason / Notes"]
    col_w = [36, 15, 15, 12, 60]
    write_title(ws, "SoC Honours Project – Reserved / Unused Address Space", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    rows = [
        ("Gap: 0x0000_0000–0x0001_FFFF interior\n(between Instr Mem and Data Mem)",
         "0x0000_0000", "0x0001_FFFF", "128 KB",
         "Occupied by Instruction Memory (0x0000_0000) and Data Memory (0x0001_0000). "
         "No unused gap here."),
        ("Gap: above Data Memory to UART",
         "0x0002_0000", "0x0002_0FFF", "4 KB",
         "UART occupies this range. No gap."),
        ("GAP: 0x0003_0000 – 0x0003_FFFF",
         "0x0003_0000", "0x0003_FFFF", "64 KB",
         "UNALLOCATED. Available for future IP. "
         "Previously the existing interconnect packed peripherals "
         "tightly at 0x0002_x000; the new map gives each IP a clean "
         "64 KB-boundary base, leaving this gap free."),
        ("Timer slot (IP pending)",
         "0x0004_0000", "0x0004_0FFF", "4 KB",
         "Reserved for Timer IP. RTL not yet available. "
         "Remaining 0x0004_1000–0x0004_FFFF (60 KB) is expansion space."),
        ("GPIO slot (IP pending)",
         "0x0005_0000", "0x0005_0FFF", "4 KB",
         "Reserved for GPIO IP. RTL not yet available."),
        ("Packet FIFO slot (IP pending)",
         "0x0006_0000", "0x0006_0FFF", "4 KB",
         "Reserved for Packet FIFO IP. RTL not yet available."),
        ("Packet Counter slot (IP pending)",
         "0x0007_0000", "0x0007_0FFF", "4 KB",
         "Reserved for Packet Counter IP. RTL not yet available."),
        ("Enhanced Timer slot (IP pending)",
         "0x0008_0000", "0x0008_0FFF", "4 KB",
         "Reserved for Enhanced Timer IP. RTL not yet available."),
        ("CRC slot (IP pending)",
         "0x0009_0000", "0x0009_0FFF", "4 KB",
         "Reserved for CRC IP. RTL not yet available."),
        ("DMA slot (IP pending)",
         "0x000A_0000", "0x000A_FFFF", "64 KB",
         "Reserved for DMA IP. Given 64 KB because DMA controllers "
         "typically need registers for multiple channels "
         "(src addr, dst addr, length, control, status per channel)."),
        ("Interrupt Controller slot (IP pending)",
         "0x000B_0000", "0x000B_0FFF", "4 KB",
         "Reserved for external Interrupt Controller IP. "
         "Note: VeeR has its own internal PIC. This slot is for any "
         "additional team-member interrupt controller."),
        ("RLE slot (IP pending)",
         "0x000C_0000", "0x000C_0FFF", "4 KB",
         "Reserved for RLE (Run-Length Encoding) IP. RTL not yet available."),
        ("Expansion gap above known IPs",
         "0x0011_0000", "0x001F_FFFF", "~956 KB",
         "RESERVED for future IP expansion. All 5 team members can be "
         "allocated sub-regions here as their IPs are integrated. "
         "Clean 64 KB sub-regions recommended per IP."),
        ("MUST NOT USE – VeeR ICCM",
         "0xEE00_0000", "0xEE00_FFFF", "64 KB",
         "VeeR internal Instruction CCM. Hardcoded in veer.config "
         "(region 0xE, top-aligned). Must not be allocated to any peripheral."),
        ("MUST NOT USE – VeeR DCCM",
         "0xF004_0000", "0xF004_FFFF", "64 KB",
         "VeeR internal Data CCM. Hardcoded in veer.config "
         "(region 0xF, offset 0x40000). Must not be allocated to any peripheral."),
        ("MUST NOT USE – VeeR PIC",
         "0xF00C_0000", "0xF00C_7FFF", "32 KB",
         "VeeR internal PIC registers. Hardcoded in veer.config "
         "(region 0xF, offset 0xC0000). "
         "CPU accesses this range via load/store for interrupt management. "
         "Must not be allocated to any peripheral."),
        ("All other addresses",
         "0x0000_0000", "0xFFFF_FFFF", "~4 GB minus above",
         "Addresses not listed in the SoC address map are unallocated. "
         "The AXI interconnect will return DECERR for unmapped accesses. "
         "Avoid regions 0xD0000000–0xFFFFFFFF as they overlap with "
         "standard RISC-V machine-mode CSR / platform regions."),
    ]

    for i, row in enumerate(rows):
        fills = []
        for v in row:
            if "MUST NOT USE" in str(v) or "MUST NOT USE" in str(row[0]):
                fills.append("FFD7D7")
            elif "UNALLOCATED" in str(v) or "Reserved" in str(v) or "pending" in str(v):
                fills.append(WARN_AMBER)
            else:
                fills.append(None)
        write_row(ws, i + 3, list(row), alt=(i % 2 == 0), fills=fills)
        ws.row_dimensions[i + 3].height = 42

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 5 – DUPLICATE IP ANALYSIS
# ────────────────────────────────────────────────────────────────────────────
def sheet_duplicates(wb):
    ws = wb.create_sheet("Duplicate_IP_Analysis")
    NCOLS = 7
    headers = [
        "IP Name", "Instance A (Path)", "Instance B (Path)",
        "Instance C (Path)", "Comparison Result",
        "Integration Decision", "Action Required"
    ]
    col_w = [14, 36, 36, 36, 22, 28, 44]
    write_title(ws, "SoC Honours Project – Duplicate IP Analysis", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    rows = [
        (
            "UART",
            "soc_project_packet_buffering/rtl/UART_IP/src/rtl/axi_uart_top.v",
            "Honours_lab_316/axi-lite_uart-ipcore/src/rtl/axi_uart_top.v",
            "IPs/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v",
            "IDENTICAL\n(diff confirmed – byte for byte)",
            "Single integration slot.\nOne canonical copy used.",
            "Choose one canonical copy for FULL_SOC_HONOURS_PROJECT/rtl/ip/uart/. "
            "Do NOT modify internal files. "
            "Recommend: use soc_project_packet_buffering copy as it is the "
            "most recently integrated version with the existing adapter."
        ),
        (
            "AES",
            "Honours_lab_316/aes_core-master/rtl/verilog/",
            "IPs/aes_core-master/rtl/verilog/",
            "Honours_lab_316/AES-IP/aes_core-master/rtl/verilog/",
            "SAME CODEBASE\n(same filenames, same structure)",
            "Single integration slot.\nOne canonical copy used.",
            "Verify with diff. If identical, use one copy. "
            "Place in FULL_SOC_HONOURS_PROJECT/rtl/ip/aes/. "
            "If any copy has been modified, document the differences."
        ),
        (
            "I2C",
            "IPs/i2c-master/rtl/verilog/i2c_master_top.v",
            "Honours_lab_316/I2C/rtl/verilog/i2c_master_top.v",
            "N/A",
            "SAME CODEBASE\n(same author, same filenames)",
            "Single integration slot.\nOne canonical copy used.",
            "Verify with diff. If identical, use one copy. "
            "Requires AXI4-Lite→Wishbone bridge wrapper – "
            "do not modify i2c_master_top.v itself."
        ),
        (
            "Timer",
            "NOT FOUND IN REPO",
            "NOT FOUND IN REPO",
            "N/A",
            "NO RTL AVAILABLE",
            "Slot reserved at 0x0004_0000.\nPending from team.",
            "Obtain Timer RTL from the responsible team member. "
            "Compare if multiple versions exist. "
            "Do not assume identical until confirmed."
        ),
        (
            "FIFO\n(Packet FIFO)",
            "NOT FOUND IN REPO",
            "NOT FOUND IN REPO",
            "N/A",
            "NO RTL AVAILABLE",
            "Slot reserved at 0x0006_0000.\nPending from team.",
            "Note: the UART IP contains an internal FIFO (axi_internal_fifo.v) "
            "but this is NOT a standalone FIFO IP. "
            "Obtain standalone FIFO RTL from team."
        ),
    ]

    for i, row in enumerate(rows):
        fills = []
        for v in row:
            if "NOT FOUND" in str(v) or "NO RTL" in str(v):
                fills.append(WARN_AMBER)
            elif "IDENTICAL" in str(v):
                fills.append(OK_GREEN)
            elif "SAME CODEBASE" in str(v):
                fills.append("D9EAD3")
            else:
                fills.append(None)
        write_row(ws, i + 3, list(row), alt=(i % 2 == 0), fills=fills)
        ws.row_dimensions[i + 3].height = 72

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 6 – ADAPTERS / WRAPPERS
# ────────────────────────────────────────────────────────────────────────────
def sheet_adapters(wb):
    ws = wb.create_sheet("Adapters_Wrappers")
    NCOLS = 8
    headers = [
        "Adapter / Wrapper Name", "Required For",
        "CPU-Side Interface", "IP-Side Interface",
        "Key Conversion Tasks", "Status",
        "Source File (if existing)", "Priority"
    ]
    col_w = [30, 22, 22, 22, 44, 16, 38, 12]
    write_title(ws, "SoC Honours Project – Required Adapters and Wrappers", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    rows = [
        (
            "veer_lsu_axi64_to_axi32\n(AXI4 64-bit → AXI4 32-bit)",
            "ALL peripherals on the LSU path",
            "AXI4, 64-bit data, 32-bit addr,\n8-bit wstrb, ID=LSU_BUS_TAG (4b)",
            "AXI4, 32-bit data, 32-bit addr,\n4-bit wstrb, ID=8b",
            "• Split 64-bit write data to lower/upper 32-bit word\n"
            "• Select correct 32-bit word based on address LSB [2]\n"
            "• Convert 8-bit byte strobe to 4-bit\n"
            "• Zero-extend read data from 32→64 bit\n"
            "• Pass-through all AXI handshake signals\n"
            "• Handle AXI4 ID width mismatch",
            "TO BE CREATED",
            "Described in KIRO_DESCRIPTION.txt.\n"
            "axi4_to_axi4lite_uart_adapter.v exists but is UART-specific only.",
            "HIGH\n(blocks all LSU integration)"
        ),
        (
            "veer_ifu_axi64_to_axi32\n(AXI4 64-bit → AXI4 32-bit for IFU)",
            "Instruction Memory\n(IFU fetch path)",
            "AXI4, 64-bit data, 32-bit addr,\nIFU_BUS_TAG ID (derived)",
            "AXI4, 32-bit data, 32-bit addr",
            "• 64-bit fetch data reassembly for 32-bit instruction memory\n"
            "• IFU typically issues read-only burst transactions\n"
            "• Must handle AXI arlen/arsize correctly",
            "TO BE CREATED",
            "None existing.",
            "HIGH\n(IFU cannot fetch if not present)"
        ),
        (
            "axi4_to_axi4lite_uart_adapter\n(AXI4 → AXI4-Lite for UART)",
            "UART IP",
            "AXI4, 32-bit data, 32-bit addr,\n8-bit ID",
            "AXI4-Lite style, 32-bit data,\n5-bit addr, 12-bit ID",
            "• Buffer AW and W independently\n"
            "• Present AWVALID+WVALID together to UART\n"
            "• Address truncation [31:0]→[4:0]\n"
            "• ID zero-extension 8b→12b and truncation on response\n"
            "• No burst support (UART is register peripheral)",
            "EXISTS IN REPO",
            "soc_project_packet_buffering/rtl/\naxi4_to_axi4lite_uart_adapter.v",
            "DONE\n(already integrated)"
        ),
        (
            "axi4_to_axi4lite_spi_adapter\n(AXI4 → AXI4-Lite for SPI)",
            "SPI IP",
            "AXI4, 32-bit data, 32-bit addr,\n8-bit ID",
            "AXI4-Lite style, 32-bit data,\n7-bit addr, 12-bit ID",
            "• Similar to UART adapter\n"
            "• Address truncation [31:0]→[6:0]\n"
            "• ID conversion 8b→12b\n"
            "• No burst support",
            "TO BE CREATED\n(model on UART adapter)",
            "None. Model after axi4_to_axi4lite_uart_adapter.v",
            "HIGH"
        ),
        (
            "axi4lite_to_wishbone_i2c_bridge\n(AXI4-Lite → Wishbone for I2C)",
            "I2C IP",
            "AXI4-Lite, 32-bit data, 32-bit addr",
            "Wishbone rev-B2, 8-bit data,\n3-bit addr, wb_cyc+wb_stb+wb_we",
            "• Protocol conversion: AXI4-Lite → Wishbone\n"
            "• Data width conversion: 32-bit → 8-bit\n"
            "• Address mapping: AXI byte addr → wb_adr_i[2:0]\n"
            "• Single-beat only (I2C regs are 8-bit)\n"
            "• Map wb_ack_o → AXI BVALID/RVALID\n"
            "• Route wb_inta_o as interrupt output",
            "TO BE CREATED",
            "None existing in repo.",
            "HIGH\n(I2C cannot work without this)"
        ),
        (
            "axi4_to_axi4lite_pwm_adapter\n(AXI4 → AXI4-Lite for PWM)",
            "PWM IP",
            "AXI4, 32-bit data, 32-bit addr,\n8-bit ID",
            "AXI4-Lite, 32-bit data,\n4-bit addr (NO ID signals)",
            "• Address truncation [31:0]→[3:0]\n"
            "• Strip AXI ID (PWM has no ID ports)\n"
            "• No burst support",
            "TO BE CREATED",
            "None. Can model after UART adapter but simpler (no ID on slave).",
            "MEDIUM"
        ),
        (
            "axi64_to_axi32_aes_wrapper\n(AXI4 64-bit → AXI4 32-bit for AES)",
            "AES IP",
            "AXI4, 64-bit data (from LSU adapter),\nor direct 32-bit if LSU adapter used",
            "AXI4 full, 32-bit data, 32-bit addr,\n8-bit ID",
            "• If general LSU adapter already reduces to 32-bit,\n  AES connects directly to interconnect\n"
            "• AES uses AXI4 full (not Lite) – no additional Lite bridge needed\n"
            "• Verify rst polarity: aes_cipher_top uses ACTIVE-LOW reset",
            "NO EXTRA ADAPTER NEEDED\n(if general LSU 64→32 adapter used)",
            "aes_register_set.v + axi_aes_slave.v\n(already AXI4 full slave)",
            "LOW\n(AXI4 native)"
        ),
    ]

    for i, row in enumerate(rows):
        fills = []
        for v in row:
            if "TO BE CREATED" in str(v):
                fills.append(WARN_AMBER)
            elif "EXISTS IN REPO" in str(v) or "DONE" in str(v):
                fills.append(OK_GREEN)
            elif "NO EXTRA ADAPTER NEEDED" in str(v):
                fills.append(OK_GREEN)
            else:
                fills.append(None)
        write_row(ws, i + 3, list(row), alt=(i % 2 == 0), fills=fills)
        ws.row_dimensions[i + 3].height = 96

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 7 – VeeR EL2 INTERFACE SUMMARY
# ────────────────────────────────────────────────────────────────────────────
def sheet_veer(wb):
    ws = wb.create_sheet("VeeR_EL2_Interface")
    NCOLS = 5
    headers = ["Interface / Signal Group", "Direction (CPU)", "Width", "Protocol", "Notes"]
    col_w = [34, 18, 18, 18, 56]
    write_title(ws, "VeeR EL2 CPU Interface Summary (from el2_veer_wrapper.sv)", NCOLS)
    write_col_headers(ws, headers, 2)
    set_col_widths(ws, col_w)

    rows = [
        # Global
        ("── Global ──", "", "", "", ""),
        ("clk", "Input", "1", "–", "Primary clock."),
        ("rst_l", "Input", "1", "–", "Active-LOW synchronous reset."),
        ("dbg_rst_l", "Input", "1", "–", "Debug reset, active-LOW."),
        ("rst_vec[31:1]", "Input", "31", "–", "Reset vector. Default 0x8000_0000 (testbench). Tie to constant in top-level."),
        ("nmi_int", "Input", "1", "–", "Non-maskable interrupt."),
        ("nmi_vec[31:1]", "Input", "31", "–", "NMI handler address. Tie to constant."),
        ("jtag_id[31:1]", "Input", "31", "–", "JTAG ID. Tie to constant."),

        # LSU AXI master
        ("── LSU AXI Master (Load/Store) ──", "", "", "", ""),
        ("lsu_axi_awaddr[31:0]", "Output", "32", "AXI4", "Write address."),
        ("lsu_axi_awvalid / awready", "Out/In", "1", "AXI4", "Write address handshake."),
        ("lsu_axi_awid[LSU_BUS_TAG-1:0]", "Output", "4 (default)", "AXI4", "Write transaction ID. LSU_BUS_TAG=4 by default."),
        ("lsu_axi_awlen[7:0]", "Output", "8", "AXI4", "Burst length. Tied to 0 (single beat) by LSU."),
        ("lsu_axi_awsize[2:0]", "Output", "3", "AXI4", "Transfer size. Max 3'b011 = 8 bytes (64-bit)."),
        ("lsu_axi_awburst[1:0]", "Output", "2", "AXI4", "Burst type. Tied to INCR by LSU."),
        ("lsu_axi_wdata[63:0]", "Output", "64", "AXI4", "DATA BUS IS 64-BIT. Width mismatch with 32-bit IPs."),
        ("lsu_axi_wstrb[7:0]", "Output", "8", "AXI4", "8-bit byte strobe (one bit per byte of 64-bit data)."),
        ("lsu_axi_wvalid / wready", "Out/In", "1", "AXI4", "Write data handshake."),
        ("lsu_axi_wlast", "Output", "1", "AXI4", "End of burst. Always 1 for single beat."),
        ("lsu_axi_bresp[1:0]", "Input", "2", "AXI4", "Write response: 00=OKAY, 10=SLVERR, 11=DECERR."),
        ("lsu_axi_bid[LSU_BUS_TAG-1:0]", "Input", "4", "AXI4", "Write response ID."),
        ("lsu_axi_araddr[31:0]", "Output", "32", "AXI4", "Read address."),
        ("lsu_axi_arvalid / arready", "Out/In", "1", "AXI4", "Read address handshake."),
        ("lsu_axi_arid[LSU_BUS_TAG-1:0]", "Output", "4", "AXI4", "Read transaction ID."),
        ("lsu_axi_rdata[63:0]", "Input", "64", "AXI4", "Read data. 64-BIT. Must pad from 32-bit peripheral."),
        ("lsu_axi_rresp[1:0]", "Input", "2", "AXI4", "Read response."),
        ("lsu_axi_rid[LSU_BUS_TAG-1:0]", "Input", "4", "AXI4", "Read data ID."),
        ("lsu_axi_rlast", "Input", "1", "AXI4", "Last read data beat."),

        # IFU AXI master
        ("── IFU AXI Master (Instruction Fetch) ──", "", "", "", ""),
        ("ifu_axi_araddr[31:0]", "Output", "32", "AXI4", "Instruction fetch address."),
        ("ifu_axi_arvalid / arready", "Out/In", "1", "AXI4", "Read address handshake."),
        ("ifu_axi_arid[IFU_BUS_TAG-1:0]", "Output", "derived", "AXI4", "IFU transaction ID. Width is derived (default 4)."),
        ("ifu_axi_rdata[63:0]", "Input", "64", "AXI4", "Fetched instruction data. 64-BIT. IFU reads 64-bit chunks."),
        ("ifu_axi_rresp[1:0]", "Input", "2", "AXI4", "Read response."),
        ("ifu_axi_rlast", "Input", "1", "AXI4", "Last read beat."),
        ("IFU write channel", "Output", "–", "AXI4", "All tied to 0 by IFU (instruction fetch is read-only in practice). Pragma coverage off."),

        # SB AXI master
        ("── SB AXI Master (System Bus / Debug) ──", "", "", "", ""),
        ("sb_axi_awaddr[31:0]", "Output", "32", "AXI4", "Debug write address."),
        ("sb_axi_wdata[63:0]", "Output", "64", "AXI4", "Debug write data. 64-BIT."),
        ("sb_axi_wstrb[7:0]", "Output", "8", "AXI4", "8-bit byte strobe."),
        ("sb_axi_araddr[31:0]", "Output", "32", "AXI4", "Debug read address."),
        ("sb_axi_rdata[63:0]", "Input", "64", "AXI4", "Debug read data. 64-BIT."),
        ("sb_axi_awid / arid [SB_BUS_TAG-1:0]", "Output", "1", "AXI4", "SB_BUS_TAG = 1 bit by default."),

        # DMA AXI slave
        ("── DMA AXI Slave (external DMA writes into CPU DCCM/ICCM) ──", "", "", "", ""),
        ("dma_axi_awaddr[31:0]", "Input", "32", "AXI4", "DMA writes into CPU memory."),
        ("dma_axi_wdata[63:0]", "Input", "64", "AXI4", "DMA data bus. 64-BIT."),
        ("dma_axi_wstrb[7:0]", "Input", "8", "AXI4", "8-bit strobe."),
        ("dma_axi_rdata[63:0]", "Output", "64", "AXI4", "DMA read data. 64-BIT."),
        ("dma_axi_awid/arid [DMA_BUS_TAG-1:0]", "Input", "1", "AXI4", "DMA_BUS_TAG = 1 bit."),

        # Interrupts
        ("── Interrupt Interface ──", "", "", "", ""),
        ("timer_int", "Input", "1", "–", "Timer interrupt. Connect to Timer IP's irq output."),
        ("soft_int", "Input", "1", "–", "Software interrupt."),
        ("extintsrc_req[pt.PIC_TOTAL_INT:1]", "Input", "31 (default)", "–",
         "External interrupt sources [31:1]. Connect to peripheral IRQ outputs. "
         "PIC_TOTAL_INT = 31 by default (configurable)."),

        # JTAG
        ("── JTAG Interface ──", "", "", "", ""),
        ("jtag_tck / jtag_tms / jtag_tdi / jtag_tdo", "In/In/In/Out", "1 each", "JTAG", "Standard JTAG debug interface."),
        ("jtag_trst_n", "Input", "1", "JTAG", "JTAG async reset, active-LOW."),

        # Internal memory addresses
        ("── VeeR Internal Memory Addresses (from veer.config) ──", "", "", "", ""),
        ("DCCM: region=0xF, offset=0x40000", "–", "–", "–",
         "Address = 256M × 0xF + 0x40000 = 0xF004_0000. Size=64KB."),
        ("ICCM: region=0xE, top-aligned", "–", "–", "–",
         "Top-aligned in region 0xE. Address ≈ 0xEE00_0000. Size=64KB."),
        ("PIC: region=0xF, offset=0xC0000", "–", "–", "–",
         "Address = 0xF00C_0000. Size=32KB. PIC_TOTAL_INT=31."),
        ("reset_vec (default)", "–", "–", "–", "0x8000_0000. Overridable. CPU starts fetching from this address."),
    ]

    r = 3
    for row in rows:
        r += 1
        if row[1] == "" and row[2] == "" and "──" in str(row[0]):
            ws.row_dimensions[r].height = 14
            c = ws.cell(row=r, column=1, value=row[0])
            c.font = Font(bold=True, size=10, color="FFFFFF")
            c.fill = _fill(HDR_MID)
            c.alignment = _left()
            ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=NCOLS)
        else:
            fills = [None] * NCOLS
            if "64-BIT" in str(row[4]) or "64-BIT" in str(row[2]):
                fills[2] = "FFE699"  # amber for 64-bit width
                fills[4] = "FFE699"
            write_row(ws, r, list(row), fills=fills)
            ws.row_dimensions[r].height = 28

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  SHEET 8 – INTEGRATION ARCHITECTURE
# ────────────────────────────────────────────────────────────────────────────
def sheet_architecture(wb):
    ws = wb.create_sheet("Integration_Architecture")
    ws.column_dimensions['A'].width = 120

    write_title(ws, "SoC Honours Project – High-Level Integration Architecture (Phase 1)", 1)

    lines = [
        "",
        "CONFIRMED FROM ACTUAL RTL FILES – NOT ASSUMED",
        "",
        "All interfaces, widths, and protocols below are taken directly from:",
        "  • el2_veer_wrapper.sv (VeeR EL2 AXI interface)",
        "  • axi_uart_top.v + axi_uart.vh + axi_uart_defines.vh (UART)",
        "  • axi_spi_top.v + axi_spi.vh + axi_spi_defines.vh (SPI)",
        "  • i2c_master_top.v + i2c_master_defines.v (I2C)",
        "  • axi_aes_slave.v + aes_register_set.v (AES)",
        "  • myip_v1_0_S00_AXI.v + myip_v1_0.v (PWM)",
        "  • axi_interconnect_wrap_1x8.v / axi_interconnect_wrap_3x8.v",
        "  • axi4_to_axi4lite_uart_adapter.v",
        "  • configs/veer.config",
        "",
        "═" * 100,
        "",
        "                         ┌─────────────────────────────────────────────┐",
        "                         │          VeeR EL2 RISC-V CPU                │",
        "                         │  xlen=32, regwidth=32, BUS DATA = 64-bit    │",
        "                         │  AXI4 protocol (RV_BUILD_AXI4)              │",
        "                         │  reset_vec = 0x8000_0000                    │",
        "                         └────────┬─────────┬──────────┬───────────────┘",
        "                                  │ LSU     │ IFU      │ DMA (slave)",
        "                                  │ AXI4    │ AXI4     │ AXI4",
        "                                  │ 64-bit  │ 64-bit   │ 64-bit",
        "                                  │         │          │",
        "                    ┌─────────────▼─┐   ┌───▼────────┐ │",
        "                    │ veer_lsu_axi  │   │veer_ifu_axi│ │",
        "                    │ 64→32 adapter │   │64→32 adapter│ │",
        "                    │ (TO CREATE)   │   │(TO CREATE) │ │",
        "                    └──────┬────────┘   └─────┬──────┘ │",
        "                           │ AXI4             │ AXI4   │",
        "                           │ 32-bit           │ 32-bit │",
        "                           │                  │        │",
        "         ┌─────────────────▼──────────────────▼────────┘",
        "         │                                              │",
        "         │       SoC AXI Interconnect                  │",
        "         │   (axi_interconnect_wrap_NxM)               │",
        "         │   32-bit data, 32-bit addr                  │",
        "         │   Address decoding per SoC memory map       │",
        "         │                                             │",
        "         └──┬──────┬──────┬────┬────┬────┬────┬────┬──┘",
        "            │      │      │    │    │    │    │    │",
        "         [0x0000] [0x0001][0x0002][0x000D][0x000E][0x000F][0x0010][0x000A+]",
        "            │      │      │    │    │    │    │    │",
        "          Instr   Data   UART SPI  I2C  AES  PWM  [Future]",
        "          Mem     Mem   Adapter Adapter Bridge      IPs",
        "         (RTL     (RTL  │    │    │    (AXI4  Adapter",
        "         TBD)     TBD)  │    │    │   native) │",
        "                        │    │    │          │",
        "                   axi_uart axi_spi axi4lite→WB PWM→Lite",
        "                   _top.v  _top.v  i2c_master  adapter",
        "                   (AXI4L) (AXI4L) _top.v(WB)  (TO CREATE)",
        "",
        "═" * 100,
        "",
        "KEY FACTS FROM RTL ANALYSIS:",
        "",
        "1. VeeR EL2 data buses are ALL 64-bit (LSU, IFU, SB, DMA).",
        "   Address buses are all 32-bit.",
        "   A 64-bit→32-bit AXI width adapter IS REQUIRED on every outbound CPU bus.",
        "",
        "2. The existing axi4_to_axi4lite_uart_adapter.v handles UART specifically.",
        "   A general veer_lsu_axi64_to_axi32 adapter must be created for all other IPs.",
        "",
        "3. UART (AXI4-Lite style, 32-bit, 5-bit addr) – CONFIRMED RTL, identical across all 3 copies.",
        "   Requires: (a) 64→32 LSU adapter  (b) existing AXI4→Lite UART adapter.",
        "",
        "4. SPI (AXI4-Lite style, 32-bit, 7-bit addr) – CONFIRMED RTL.",
        "   Requires: (a) 64→32 LSU adapter  (b) new AXI4→Lite SPI adapter (model on UART adapter).",
        "",
        "5. I2C (Wishbone rev-B2, 8-bit data, 3-bit addr) – CONFIRMED RTL.",
        "   Requires: (a) 64→32 LSU adapter  (b) NEW AXI4-Lite→Wishbone bridge (not yet in repo).",
        "   Data width mismatch: 32-bit AXI ↔ 8-bit Wishbone – bridge must handle this.",
        "",
        "6. AES (AXI4 full, 32-bit data, 32-bit addr) – CONFIRMED RTL.",
        "   Requires: 64→32 LSU adapter only. No Lite bridge needed (AXI4 full native).",
        "   NOTE: aes_cipher_top reset is ACTIVE-LOW – connect carefully.",
        "",
        "7. PWM (AXI4-Lite, 32-bit data, 4-bit addr, NO ID signals) – CONFIRMED RTL.",
        "   Requires: (a) 64→32 LSU adapter  (b) new AXI4→Lite PWM adapter (strip ID).",
        "",
        "8. IPs NOT YET AVAILABLE (RTL pending from team):",
        "   Timer, GPIO, Packet FIFO, Packet Counter, Enhanced Timer,",
        "   CRC, DMA, Interrupt Controller, RLE.",
        "   Slots reserved in address map. Cannot design adapters until RTL is available.",
        "",
        "9. VeeR internal regions MUST be protected in the interconnect:",
        "   DCCM 0xF004_0000–0xF004_FFFF  (64 KB)",
        "   ICCM 0xEE00_0000–0xEE00_FFFF  (64 KB)",
        "   PIC  0xF00C_0000–0xF00C_7FFF  (32 KB)",
        "   These must not be decoded to any peripheral.",
        "",
        "═" * 100,
        "",
        "INTERCONNECT DECODE TABLE (for implementing axi_interconnect_wrap_NxM):",
        "",
        f"  {'Slot':<5} {'IP Name':<28} {'Base Addr':<14} {'End Addr':<14} {'Size':<10} {'Adapter Required'}",
        f"  {'-'*5} {'-'*28} {'-'*14} {'-'*14} {'-'*10} {'-'*40}",
        f"  {'M00':<5} {'Instruction Memory':<28} {'0x0000_0000':<14} {'0x0000_FFFF':<14} {'64 KB':<10} {'64→32 IFU adapter'}",
        f"  {'M01':<5} {'Data Memory':<28} {'0x0001_0000':<14} {'0x0001_FFFF':<14} {'64 KB':<10} {'64→32 LSU adapter'}",
        f"  {'M02':<5} {'UART':<28} {'0x0002_0000':<14} {'0x0002_0FFF':<14} {'4 KB':<10} {'64→32 + AXI4→Lite UART adapter (EXISTS)'}",
        f"  {'M03':<5} {'Timer (pending)':<28} {'0x0004_0000':<14} {'0x0004_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M04':<5} {'GPIO (pending)':<28} {'0x0005_0000':<14} {'0x0005_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M05':<5} {'Packet FIFO (pending)':<28} {'0x0006_0000':<14} {'0x0006_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M06':<5} {'Packet Counter (pending)':<28} {'0x0007_0000':<14} {'0x0007_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M07':<5} {'Enhanced Timer (pending)':<28} {'0x0008_0000':<14} {'0x0008_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M08':<5} {'CRC (pending)':<28} {'0x0009_0000':<14} {'0x0009_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M09':<5} {'DMA (pending)':<28} {'0x000A_0000':<14} {'0x000A_FFFF':<14} {'64 KB':<10} {'TBD – may need 64-bit path'}",
        f"  {'M10':<5} {'Interrupt Ctrl (pending)':<28} {'0x000B_0000':<14} {'0x000B_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M11':<5} {'RLE (pending)':<28} {'0x000C_0000':<14} {'0x000C_0FFF':<14} {'4 KB':<10} {'TBD – IP RTL not available'}",
        f"  {'M12':<5} {'SPI':<28} {'0x000D_0000':<14} {'0x000D_0FFF':<14} {'4 KB':<10} {'64→32 + AXI4→Lite SPI adapter (TO CREATE)'}",
        f"  {'M13':<5} {'I2C':<28} {'0x000E_0000':<14} {'0x000E_0FFF':<14} {'4 KB':<10} {'64→32 + AXI4-Lite→Wishbone bridge (TO CREATE)'}",
        f"  {'M14':<5} {'AES':<28} {'0x000F_0000':<14} {'0x000F_0FFF':<14} {'4 KB':<10} {'64→32 LSU adapter only (AXI4 native)'}",
        f"  {'M15':<5} {'PWM':<28} {'0x0010_0000':<14} {'0x0010_0FFF':<14} {'4 KB':<10} {'64→32 + AXI4→Lite PWM adapter (TO CREATE)'}",
        "",
        "═" * 100,
        "",
        "UNRESOLVED ITEMS – REQUIRED FROM TEAM BEFORE PHASE 2:",
        "",
        "  1. RTL for: Timer, GPIO, Packet FIFO, Packet Counter, Enhanced Timer,",
        "              CRC, DMA, Interrupt Controller, RLE",
        "  2. Confirmation whether Timer is the same IP as Enhanced Timer or different",
        "  3. Bus protocol for each missing IP (AXI4 / AXI4-Lite / APB / custom?)",
        "  4. Data width of each missing IP",
        "  5. Register map for each missing IP",
        "  6. Interrupt output signal names for each IP that has an interrupt",
        "  7. Whether any team member has developed a 2nd UART with different functionality",
        "  8. Confirmation of reset_vec address for the final SoC",
        "  9. Target FPGA / technology (affects memory implementation for Instr/Data memory)",
        " 10. PWM register function definitions (slv_reg0–3 not documented in RTL)",
    ]

    for i, line in enumerate(lines):
        r = i + 2
        ws.row_dimensions[r].height = 16 if "═" not in line else 6
        c = ws.cell(row=r, column=1, value=line)
        c.alignment = Alignment(horizontal="left", vertical="center",
                                wrap_text=False)
        c.font = Font(size=10, name="Courier New" if "│" in line or "┌" in line
                      or "═" in line or "M0" in line or "──" in line else "Calibri")
        if "CONFIRMED FROM" in line or "KEY FACTS" in line or \
           "UNRESOLVED" in line or "INTERCONNECT DECODE" in line:
            c.font = Font(bold=True, size=11)
            c.fill = _fill(HDR_LIGHT)

    return ws


# ────────────────────────────────────────────────────────────────────────────
#  MAIN
# ────────────────────────────────────────────────────────────────────────────
def main():
    wb = Workbook()
    # Remove default sheet
    wb.remove(wb.active)

    sheet_ip_inventory(wb)
    sheet_address_map(wb)
    sheet_register_map(wb)
    sheet_reserved(wb)
    sheet_duplicates(wb)
    sheet_adapters(wb)
    sheet_veer(wb)
    sheet_architecture(wb)

    out = ("/home/student/Documents/316/FULL_SOC_HONOURS_PROJECT"
           "/docs/phase1/SoC_Honours_Phase1_Report.xlsx")
    wb.save(out)
    print(f"Saved: {out}")

if __name__ == "__main__":
    main()
