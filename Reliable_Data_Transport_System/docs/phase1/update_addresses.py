#!/usr/bin/env python3
"""
update_addresses.py
────────────────────
Modifies SoC_Honours_Phase1_Report.xlsx in-place to reflect:
  Data Memory   64 KB → 128 KB   (0x0001_0000 – 0x0002_FFFF)
  All peripherals shifted by +0x0001_0000 (one 64 KB page)

Old peripheral start: 0x0002_0000
New peripheral start: 0x0003_0000

Approach:
  • Load the workbook with openpyxl (data_only=False to preserve formulas).
  • For every cell whose value contains an old address string, replace it
    with the new address string.
  • Also replace text-embedded occurrences inside multi-line strings.
  • Preserve all cell styles, fills, fonts, borders untouched.
"""

import re
import copy
from openpyxl import load_workbook
from openpyxl.utils import get_column_letter

XLSX = ("/home/student/Documents/316/FULL_SOC_HONOURS_PROJECT"
        "/docs/phase1/SoC_Honours_Phase1_Report.xlsx")

# ── Address translation table ────────────────────────────────────────────────
# Order matters: longer / more-specific strings must come before shorter ones
# so that e.g. "0x0002_0FFF" is replaced before "0x0002" could partially match.
# All hex letters are upper-case to match the workbook convention.
#
# Each entry: (old_string, new_string)
# We also add underscore-less variants for the Interconnect Decode Table
# which uses plain spacing alignment (no underscores in some cells).

ADDR_MAP = [
    # ── Data Memory ──────────────────────────────────────────────────────────
    # End address changes; base address stays the same
    ("0x0001_FFFF",  "0x0002_FFFF"),   # Data Memory end addr
    ("0x0001_FFFF",  "0x0002_FFFF"),   # (duplicate-safe; openpyxl replaces all)

    # ── Peripheral base+end addresses (old → new) ────────────────────────────
    # UART  0x0002_0000–0x0002_0FFF  →  0x0003_0000–0x0003_0FFF
    ("0x0002_0FFF",  "0x0003_0FFF"),
    ("0x0002_0000",  "0x0003_0000"),

    # Timer 0x0004_0000–0x0004_0FFF  →  0x0005_0000–0x0005_0FFF
    ("0x0004_0FFF",  "0x0005_0FFF"),
    ("0x0004_0000",  "0x0005_0000"),

    # GPIO  0x0005_0000–0x0005_0FFF  →  0x0006_0000–0x0006_0FFF
    ("0x0005_0FFF",  "0x0006_0FFF"),
    ("0x0005_0000",  "0x0006_0000"),

    # Packet FIFO  0x0006_0000–0x0006_0FFF  →  0x0007_0000–0x0007_0FFF
    ("0x0006_0FFF",  "0x0007_0FFF"),
    ("0x0006_0000",  "0x0007_0000"),

    # Packet Counter 0x0007_0000–0x0007_0FFF  →  0x0008_0000–0x0008_0FFF
    ("0x0007_0FFF",  "0x0008_0FFF"),
    ("0x0007_0000",  "0x0008_0000"),

    # Enhanced Timer 0x0008_0000–0x0008_0FFF  →  0x0009_0000–0x0009_0FFF
    ("0x0008_0FFF",  "0x0009_0FFF"),
    ("0x0008_0000",  "0x0009_0000"),

    # CRC  0x0009_0000–0x0009_0FFF  →  0x000A_0000–0x000A_0FFF
    ("0x0009_0FFF",  "0x000A_0FFF"),
    ("0x0009_0000",  "0x000A_0000"),

    # DMA  0x000A_0000–0x000A_FFFF  →  0x000B_0000–0x000B_FFFF
    ("0x000A_FFFF",  "0x000B_FFFF"),
    ("0x000A_FFFF",  "0x000B_FFFF"),  # safe duplicate
    ("0x000A_0000",  "0x000B_0000"),

    # Interrupt Controller 0x000B_0000–0x000B_0FFF  →  0x000C_0000–0x000C_0FFF
    ("0x000B_0FFF",  "0x000C_0FFF"),
    ("0x000B_0000",  "0x000C_0000"),

    # RLE  0x000C_0000–0x000C_0FFF  →  0x000D_0000–0x000D_0FFF
    ("0x000C_0FFF",  "0x000D_0FFF"),
    ("0x000C_0000",  "0x000D_0000"),

    # SPI  0x000D_0000–0x000D_0FFF  →  0x000E_0000–0x000E_0FFF
    ("0x000D_0FFF",  "0x000E_0FFF"),
    ("0x000D_001C",  "0x000E_001C"),
    ("0x000D_0020",  "0x000E_0020"),
    ("0x000D_0028",  "0x000E_0028"),
    ("0x000D_0030",  "0x000E_0030"),
    ("0x000D_0040",  "0x000E_0040"),
    ("0x000D_0060",  "0x000E_0060"),
    ("0x000D_0064",  "0x000E_0064"),
    ("0x000D_0068",  "0x000E_0068"),
    ("0x000D_006C",  "0x000E_006C"),
    ("0x000D_0070",  "0x000E_0070"),
    ("0x000D_0074",  "0x000E_0074"),
    ("0x000D_0078",  "0x000E_0078"),
    ("0x000D_0000",  "0x000E_0000"),

    # I2C  0x000E_0000–0x000E_0FFF  →  0x000F_0000–0x000F_0FFF
    ("0x000E_0FFF",  "0x000F_0FFF"),
    ("0x000E_0007",  "0x000F_0007"),
    ("0x000E_0004",  "0x000F_0004"),
    ("0x000E_0003",  "0x000F_0003"),
    ("0x000E_0002",  "0x000F_0002"),
    ("0x000E_0001",  "0x000F_0001"),
    ("0x000E_0000",  "0x000F_0000"),

    # AES  0x000F_0000–0x000F_0FFF  →  0x0010_0000–0x0010_0FFF
    ("0x000F_0FFF",  "0x0010_0FFF"),
    ("0x000F_003C",  "0x0010_003C"),
    ("0x000F_0038",  "0x0010_0038"),
    ("0x000F_0034",  "0x0010_0034"),
    ("0x000F_0030",  "0x0010_0030"),
    ("0x000F_002C",  "0x0010_002C"),
    ("0x000F_0028",  "0x0010_0028"),
    ("0x000F_0024",  "0x0010_0024"),
    ("0x000F_0020",  "0x0010_0020"),
    ("0x000F_001C",  "0x0010_001C"),
    ("0x000F_0018",  "0x0010_0018"),
    ("0x000F_0014",  "0x0010_0014"),
    ("0x000F_0010",  "0x0010_0010"),
    ("0x000F_0004",  "0x0010_0004"),
    ("0x000F_0000",  "0x0010_0000"),

    # PWM  0x0010_0000–0x0010_0FFF  →  0x0011_0000–0x0011_0FFF
    ("0x0010_0FFF",  "0x0011_0FFF"),
    ("0x0010_000C",  "0x0011_000C"),
    ("0x0010_0008",  "0x0011_0008"),
    ("0x0010_0004",  "0x0011_0004"),
    ("0x0010_0000",  "0x0011_0000"),

    # Future expansion bank start
    ("0x0011_0000",  "0x0012_0000"),

    # ── Interconnect decode table rows (no-underscore plain hex in text) ──────
    # These appear in Integration_Architecture as plain-spaced text columns.
    # Pattern: "0x0002_0000" style already covered above for underscore forms.
    # Also handle the unformatted version used in the ASCII table column:
    #   "0x0001_FFFF" → "0x0002_FFFF"  (already above)

    # ── Size string for Data Memory ──────────────────────────────────────────
    # "64 KB" is too generic – handle it per-context via the notes field text.
    # We specifically target the Data Memory notes string pattern.
    ("Expansion to 64 KB total",
     "Expansion to 128 KB total"),

    # ── Textual references inside notes / descriptions ────────────────────────
    # IP_Inventory sheet – Data Memory placeholder note
    ("Placeholder @ 0x0001_0000 in existing interconnect.",
     "Placeholder @ 0x0001_0000 in existing interconnect."),  # base addr unchanged

    # SoC_Address_Map – Data Memory size/expansion cell
    # (covered by the size cell text replacement below)

    # Reserved_Address_Space – row 3 region name references
    ("Gap: 0x0000_0000–0x0001_FFFF interior\n(between Instr Mem and Data Mem)",
     "Gap: 0x0000_0000–0x0002_FFFF interior\n(between Instr Mem and Data Mem)"),

    ("Occupied by Instruction Memory (0x0000_0000) and Data Memory (0x0001_0000). No u",
     "Occupied by Instruction Memory (0x0000_0000) and Data Memory (0x0001_0000–0x0002_FFFF). No u"),

    # Row 4 in Reserved: "Gap: above Data Memory to UART"
    ("Gap: above Data Memory to UART",
     "Gap: above extended Data Memory to UART"),

    # Row 5 in Reserved: "GAP: 0x0003_0000 – 0x0003_FFFF"
    # The OLD gap was 0x0003_0000; now the UART sits there, so this gap is gone.
    # We'll update the entire Region name and notes for that row separately
    # after the bulk replacement.

    # Duplicate_IP_Analysis – Timer slot note
    ("Slot reserved at 0x0004_0000.\nPending from team.",
     "Slot reserved at 0x0005_0000.\nPending from team."),
    ("Slot reserved at 0x0006_0000.\nPending from team.",
     "Slot reserved at 0x0007_0000.\nPending from team."),

    # IP_Inventory – Timer/GPIO/FIFO/etc notes
    ("No RTL found. Slot reserved at 0x0004_0000 in full SoC map.",
     "No RTL found. Slot reserved at 0x0005_0000 in full SoC map."),
    ("No RTL found. Slot reserved at 0x0005_0000 in full SoC map.",
     "No RTL found. Slot reserved at 0x0006_0000 in full SoC map."),
    ("No RTL found. Slot reserved at 0x0006_0000 in full SoC map.",
     "No RTL found. Slot reserved at 0x0007_0000 in full SoC map."),
    ("No RTL found. Slot reserved at 0x0007_0000 in full SoC map.",
     "No RTL found. Slot reserved at 0x0008_0000 in full SoC map."),
    ("No RTL found. Slot reserved at 0x0008_0000.",
     "No RTL found. Slot reserved at 0x0009_0000."),
    ("No RTL found. Slot reserved at 0x0009_0000.",
     "No RTL found. Slot reserved at 0x000A_0000."),
    ("No RTL found. Slot reserved at 0x000A_0000.",
     "No RTL found. Slot reserved at 0x000B_0000."),
    ("No RTL found. Slot reserved at 0x000B_0000.",
     "No RTL found. Slot reserved at 0x000C_0000."),
    ("No RTL found. Slot reserved at 0x000C_0000.",
     "No RTL found. Slot reserved at 0x000D_0000."),

    # SoC_Address_Map Timer notes – "moved from 0x0002_1000 to give full 4 KB alig"
    # (only the new base matters here; context is already handled by addr replacement)

    # ── Integration_Architecture ASCII art address labels ────────────────────
    # The ASCII art line R45: "[0x0000] [0x0001][0x0002][0x000D]..."
    ("[0x0000] [0x0001][0x0002][0x000D][0x000E][0x000F][0x0010][0x000A+]",
     "[0x0000] [0x0001][0x0003][0x000E][0x000F][0x0010][0x0011][0x000B+]"),
]

# Additional size-string updates that are IP/row specific
# (Data Memory row only – must not change other "64 KB" occurrences)
DATA_MEM_SIZE_UPDATES = [
    # SoC_Address_Map row 10 col 4 (Allocated Size) and col 6 (Expansion Space)
    # We'll handle these by finding the Data Memory row and patching directly.
]


def apply_replacements(text, replacements):
    """Apply a list of (old, new) string replacements to text."""
    if text is None:
        return text
    s = str(text)
    for old, new in replacements:
        if old in s:
            s = s.replace(old, new)
    return s


def patch_workbook(path):
    wb = load_workbook(path)

    total_changes = 0

    for ws in wb.worksheets:
        sheet_changes = 0
        for row in ws.iter_rows():
            for cell in row:
                if cell.value is None:
                    continue
                original = cell.value
                updated  = apply_replacements(original, ADDR_MAP)
                if updated != original:
                    cell.value = updated
                    sheet_changes += 1
                    total_changes += 1

        if sheet_changes:
            print(f"  Sheet '{ws.title}': {sheet_changes} cell(s) updated")

    # ── Special-case patches ──────────────────────────────────────────────────

    # 1. SoC_Address_Map – Data Memory row (row 10):
    #    Col 4 (Allocated Size): "64 KB" → "128 KB"
    #    Col 6 (Expansion Space): "Expansion to 64 KB total" → already handled
    #    Col 9 (Notes): update "General SRAM data storage. RTL not yet provided."
    ws_map = wb["SoC_Address_Map"]
    for row in ws_map.iter_rows():
        ip_cell = row[0]
        if ip_cell.value and "Data Memory" in str(ip_cell.value):
            # Col index 3 = Allocated Size (0-based → col 4 in 1-based)
            size_cell = row[3]
            if size_cell.value and "64 KB" in str(size_cell.value):
                size_cell.value = "128 KB"
                total_changes += 1
                print(f"  Sheet 'SoC_Address_Map': Data Memory size updated to 128 KB")
            # Col index 5 = Expansion Space
            exp_cell = row[5]
            if exp_cell.value:
                old_exp = str(exp_cell.value)
                new_exp = old_exp.replace("Expansion to 64 KB total",
                                          "Expansion to 128 KB total")
                if new_exp != old_exp:
                    exp_cell.value = new_exp
                    total_changes += 1
            break

    # 2. Reserved_Address_Space – update the row that described the old
    #    "GAP: 0x0003_0000 – 0x0003_FFFF" (which was free before).
    #    Now UART occupies 0x0003_0000–0x0003_0FFF, so this is no longer a gap.
    #    The row's Base/End addresses are already updated by bulk replacement.
    #    Update its Region name and Notes to reflect the new reality.
    ws_res = wb["Reserved_Address_Space"]
    for row in ws_res.iter_rows():
        region_cell = row[0]
        val = str(region_cell.value) if region_cell.value else ""
        # Old text after bulk replacement: "GAP: 0x0004_0000 – 0x0004_FFFF"
        # (because 0x0003_0000 → 0x0004_0000 via the Timer replacement)
        # Actually: the old GAP row said "GAP: 0x0003_0000 – 0x0003_FFFF"
        # After ADDR_MAP replaces 0x0004_0000 (Timer base), 0x0003 stays as-is
        # because 0x0003_0000 is the NEW UART base – it's now occupied.
        # Let's check what the text looks like after bulk pass and fix it.
        if "GAP: 0x0003_0000" in val or "GAP: 0x0004_0000" in val:
            # This row previously described the unallocated gap.
            # With the new map, 0x0003_0000 is UART, so old gap entry becomes:
            # "Gap above extended Data Memory" is now the UART slot itself.
            # Update region name to reflect new gap starting after UART at 0x0003_1000
            region_cell.value = "GAP: 0x0003_1000 – 0x0003_FFFF\n(above UART to next IP)"
            # Base address
            row[1].value = "0x0003_1000"
            # End address
            row[2].value = "0x0003_FFFF"
            # Size
            row[3].value = "~60 KB"
            # Notes
            row[4].value = (
                "PARTIALLY UNALLOCATED. UART occupies 0x0003_0000–0x0003_0FFF (4 KB). "
                "Remaining 0x0003_1000–0x0003_FFFF (~60 KB) is expansion space for UART "
                "or an additional small peripheral if needed."
            )
            total_changes += 1
            print(f"  Sheet 'Reserved_Address_Space': GAP row updated for new UART position")
            break

    # 3. Reserved_Address_Space – Row 4: "Gap: above Data Memory to UART"
    #    Base/End addresses were already shifted by bulk replacement.
    #    Update the note text to reflect UART is now at 0x0003.
    for row in ws_res.iter_rows():
        region_cell = row[0]
        val = str(region_cell.value) if region_cell.value else ""
        notes_cell = row[4]
        notes_val  = str(notes_cell.value) if notes_cell.value else ""
        if "above extended Data Memory to UART" in val:
            # Base addr is now 0x0003_0000 (UART), end is 0x0003_0FFF
            # This row says "UART occupies this range. No gap."
            notes_cell.value = "UART occupies 0x0003_0000–0x0003_0FFF. No gap between Data Memory end (0x0002_FFFF) and UART start (0x0003_0000)."
            total_changes += 1
            break

    # 4. Integration_Architecture – update Data Memory size reference in
    #    the interconnect decode table text rows.
    ws_arch = wb["Integration_Architecture"]
    for row in ws_arch.iter_rows():
        cell = row[0]
        if cell.value is None:
            continue
        v = str(cell.value)
        # Row R102: "  M01   Data Memory ... 0x0001_FFFF    64 KB ..."
        # After bulk replacement this already has 0x0002_FFFF.
        # The size "64 KB" in the decode table needs to be "128 KB" for Data Memory.
        if "M01" in v and "Data Memory" in v and "64 KB" in v:
            cell.value = v.replace("64 KB", "128 KB", 1)
            total_changes += 1
            print(f"  Sheet 'Integration_Architecture': Data Memory size in decode table updated")

    print(f"\nTotal cell updates: {total_changes}")
    wb.save(path)
    print(f"Saved: {path}")
    return wb


if __name__ == "__main__":
    print(f"Patching: {XLSX}\n")
    patch_workbook(XLSX)
