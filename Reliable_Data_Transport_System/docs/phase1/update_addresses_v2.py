#!/usr/bin/env python3
"""
update_addresses_v2.py
──────────────────────
Single-pass atomic address update using regex.
Restores from the ORIGINAL workbook (regenerated fresh) then applies all
address changes in ONE pass so there is zero chain-reaction risk.

Strategy:
  1. Regenerate the original workbook from the generator script.
  2. Apply all address substitutions in a single regex pass per cell value.
  3. Validate and save.
"""

import re
import subprocess
import sys
from openpyxl import load_workbook

DOCS   = "/home/student/Documents/316/FULL_SOC_HONOURS_PROJECT/docs/phase1"
XLSX   = f"{DOCS}/SoC_Honours_Phase1_Report.xlsx"
GEN    = f"{DOCS}/generate_phase1_excel.py"

# ── Step 1: Regenerate clean original ───────────────────────────────────────
print("Step 1: Regenerating clean original workbook …")
result = subprocess.run(["python3", GEN], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if result.returncode != 0:
    print("ERROR regenerating:", result.stderr.decode())
    sys.exit(1)
print("  ", result.stdout.decode().strip())

# ── Step 2: Define atomic address mapping ───────────────────────────────────
#
# Each tuple: (old_hex_string, new_hex_string)
# CRITICAL: These are applied with a SINGLE regex pass per cell so no
# substitution can be fed into another substitution.
#
# Format used in workbook: 0xNNNN_NNNN  (always with underscore separator)
#
# Old peripheral start: 0x0002_0000
# New peripheral start: 0x0003_0000
# Shift: +0x0001_0000
#
# Data Memory: end addr 0x0001_FFFF → 0x0002_FFFF, size 64→128 KB
#
# Peripherals shifted by +0x0001_0000 each:
#   UART      0x0002_0xxx → 0x0003_0xxx
#   Timer     0x0004_0xxx → 0x0005_0xxx
#   GPIO      0x0005_0xxx → 0x0006_0xxx
#   FIFO      0x0006_0xxx → 0x0007_0xxx
#   PktCtr    0x0007_0xxx → 0x0008_0xxx
#   EnhTimer  0x0008_0xxx → 0x0009_0xxx
#   CRC       0x0009_0xxx → 0x000A_0xxx
#   DMA       0x000A_xxxx → 0x000B_xxxx
#   IntCtrl   0x000B_0xxx → 0x000C_0xxx
#   RLE       0x000C_0xxx → 0x000D_0xxx
#   SPI       0x000D_xxxx → 0x000E_xxxx
#   I2C       0x000E_xxxx → 0x000F_xxxx
#   AES       0x000F_xxxx → 0x0010_xxxx
#   PWM       0x0010_xxxx → 0x0011_xxxx
#   FutureExp 0x0011_0000 → 0x0012_0000

# Build a dict: old_addr → new_addr
# We enumerate every specific address string that appears in the workbook.

ADDR_TABLE = {
    # ── Data Memory end address ──────────────────────────────────────────────
    "0x0001_FFFF": "0x0002_FFFF",

    # ── UART (0x0002_0xxx → 0x0003_0xxx) ────────────────────────────────────
    "0x0002_0000": "0x0003_0000",
    "0x0002_0004": "0x0003_0004",
    "0x0002_0008": "0x0003_0008",
    "0x0002_000C": "0x0003_000C",
    "0x0002_0014": "0x0003_0014",
    "0x0002_0FFF": "0x0003_0FFF",

    # ── Timer (0x0004_0000 → 0x0005_0000) ───────────────────────────────────
    "0x0004_0000": "0x0005_0000",
    "0x0004_0FFF": "0x0005_0FFF",

    # ── GPIO (0x0005_0000 → 0x0006_0000) ────────────────────────────────────
    "0x0005_0000": "0x0006_0000",
    "0x0005_0FFF": "0x0006_0FFF",

    # ── Packet FIFO (0x0006_0000 → 0x0007_0000) ─────────────────────────────
    "0x0006_0000": "0x0007_0000",
    "0x0006_0FFF": "0x0007_0FFF",

    # ── Packet Counter (0x0007_0000 → 0x0008_0000) ──────────────────────────
    "0x0007_0000": "0x0008_0000",
    "0x0007_0FFF": "0x0008_0FFF",

    # ── Enhanced Timer (0x0008_0000 → 0x0009_0000) ──────────────────────────
    "0x0008_0000": "0x0009_0000",
    "0x0008_0FFF": "0x0009_0FFF",

    # ── CRC (0x0009_0000 → 0x000A_0000) ─────────────────────────────────────
    "0x0009_0000": "0x000A_0000",
    "0x0009_0FFF": "0x000A_0FFF",

    # ── DMA (0x000A_0000–0x000A_FFFF → 0x000B_0000–0x000B_FFFF) ────────────
    "0x000A_0000": "0x000B_0000",
    "0x000A_FFFF": "0x000B_FFFF",

    # ── Interrupt Controller (0x000B_0000 → 0x000C_0000) ────────────────────
    "0x000B_0000": "0x000C_0000",
    "0x000B_0FFF": "0x000C_0FFF",

    # ── RLE (0x000C_0000 → 0x000D_0000) ─────────────────────────────────────
    "0x000C_0000": "0x000D_0000",
    "0x000C_0FFF": "0x000D_0FFF",

    # ── SPI (0x000D_0xxx → 0x000E_0xxx) ─────────────────────────────────────
    "0x000D_0000": "0x000E_0000",
    "0x000D_001C": "0x000E_001C",
    "0x000D_0020": "0x000E_0020",
    "0x000D_0028": "0x000E_0028",
    "0x000D_0030": "0x000E_0030",
    "0x000D_0040": "0x000E_0040",
    "0x000D_0060": "0x000E_0060",
    "0x000D_0064": "0x000E_0064",
    "0x000D_0068": "0x000E_0068",
    "0x000D_006C": "0x000E_006C",
    "0x000D_0070": "0x000E_0070",
    "0x000D_0074": "0x000E_0074",
    "0x000D_0078": "0x000E_0078",
    "0x000D_0FFF": "0x000E_0FFF",

    # ── I2C (0x000E_0xxx → 0x000F_0xxx) ─────────────────────────────────────
    "0x000E_0000": "0x000F_0000",
    "0x000E_0001": "0x000F_0001",
    "0x000E_0002": "0x000F_0002",
    "0x000E_0003": "0x000F_0003",
    "0x000E_0004": "0x000F_0004",
    "0x000E_0007": "0x000F_0007",
    "0x000E_0FFF": "0x000F_0FFF",

    # ── AES (0x000F_0xxx → 0x0010_0xxx) ─────────────────────────────────────
    "0x000F_0000": "0x0010_0000",
    "0x000F_0004": "0x0010_0004",
    "0x000F_0010": "0x0010_0010",
    "0x000F_0014": "0x0010_0014",
    "0x000F_0018": "0x0010_0018",
    "0x000F_001C": "0x0010_001C",
    "0x000F_0020": "0x0010_0020",
    "0x000F_0024": "0x0010_0024",
    "0x000F_0028": "0x0010_0028",
    "0x000F_002C": "0x0010_002C",
    "0x000F_0030": "0x0010_0030",
    "0x000F_0034": "0x0010_0034",
    "0x000F_0038": "0x0010_0038",
    "0x000F_003C": "0x0010_003C",
    "0x000F_0FFF": "0x0010_0FFF",

    # ── PWM (0x0010_0xxx → 0x0011_0xxx) ─────────────────────────────────────
    "0x0010_0000": "0x0011_0000",
    "0x0010_0004": "0x0011_0004",
    "0x0010_0008": "0x0011_0008",
    "0x0010_000C": "0x0011_000C",
    "0x0010_0FFF": "0x0011_0FFF",

    # ── Future expansion start ────────────────────────────────────────────────
    "0x0011_0000": "0x0012_0000",
}

# Build a single regex that matches any of the old addresses.
# Use word-boundary-like matching: the old address must not be immediately
# followed by more hex digits (to avoid partial matches).
# All keys are 12-char strings: 0xNNNN_NNNN – they are unique enough.
pattern = re.compile(
    "(" + "|".join(re.escape(k) for k in ADDR_TABLE.keys()) + ")"
)

def replace_addrs(text):
    if text is None:
        return text
    s = str(text)
    result = pattern.sub(lambda m: ADDR_TABLE[m.group(0)], s)
    return result

# ── Step 3: Apply to workbook ────────────────────────────────────────────────
print("Step 2: Applying atomic address substitutions …")
wb = load_workbook(XLSX)
total = 0

for ws in wb.worksheets:
    sheet_count = 0
    for row in ws.iter_rows():
        for cell in row:
            if cell.value is None:
                continue
            original = cell.value
            updated  = replace_addrs(original)
            if updated != original:
                cell.value = updated
                sheet_count += 1
                total += 1
    if sheet_count:
        print(f"   Sheet '{ws.title}': {sheet_count} cell(s) updated")

# ── Step 4: Targeted non-address text patches ────────────────────────────────
print("Step 3: Applying targeted text patches …")

# SoC_Address_Map – Data Memory size cell and expansion cell
ws_map = wb["SoC_Address_Map"]
for row in ws_map.iter_rows():
    if row[0].value and "Data Memory" in str(row[0].value):
        # Col 4 = Allocated Size (index 3)
        sc = row[3]
        if sc.value and "64 KB" in str(sc.value):
            sc.value = "128 KB"
            total += 1
            print("   SoC_Address_Map: Data Memory size → 128 KB")
        # Col 6 = Expansion Space (index 5)
        ec = row[5]
        if ec.value:
            old = str(ec.value)
            new = old.replace("Expansion to 64 KB total", "Expansion to 128 KB total")
            if new != old:
                ec.value = new
                total += 1
        break

# Reserved_Address_Space – update rows referencing old gap/uart positions
ws_res = wb["Reserved_Address_Space"]
for row in ws_res.iter_rows():
    region = str(row[0].value) if row[0].value else ""
    notes  = str(row[4].value) if row[4].value else ""

    # Row "Gap: above Data Memory to UART" – note text
    if "above Data Memory to UART" in region:
        row[4].value = (
            "UART occupies 0x0003_0000–0x0003_0FFF. "
            "No gap between Data Memory end (0x0002_FFFF) and UART start (0x0003_0000)."
        )
        total += 1
        print("   Reserved_Address_Space: updated 'above Data Memory to UART' notes")

    # Row "GAP: 0x0003_0000 – 0x0003_FFFF" – now UART sits at 0x0003_0000
    # After addr replacement this becomes "GAP: 0x0003_0000 – 0x0003_FFFF" still
    # (because 0x0003_0000 is not in the replacement table – it is the NEW UART base)
    if "GAP: 0x0003_0000" in region or "UNALLOCATED" in notes:
        row[0].value = "GAP: 0x0003_1000 – 0x0003_FFFF\n(above UART, below Timer)"
        row[1].value = "0x0003_1000"
        row[2].value = "0x0003_FFFF"
        row[3].value = "~60 KB"
        row[4].value = (
            "PARTIALLY UNALLOCATED. UART occupies 0x0003_0000–0x0003_0FFF (4 KB). "
            "Remaining 0x0003_1000–0x0003_FFFF (~60 KB) is expansion space for UART "
            "or additional small peripheral."
        )
        total += 1
        print("   Reserved_Address_Space: updated GAP row for new UART position")

    # Row region name "Gap: 0x0000_0000–0x0001_FFFF interior"
    if "0x0001_FFFF" in region:
        row[0].value = region.replace("0x0001_FFFF", "0x0002_FFFF")
        total += 1

    # Notes mentioning "0x0001_0000). No u" (partial truncation from dump)
    if "Data Memory (0x0001_0000). No u" in notes or "Data Memory (0x0001_0000)" in notes:
        row[4].value = notes.replace(
            "Data Memory (0x0001_0000). No u",
            "Data Memory (0x0001_0000–0x0002_FFFF). No u"
        ).replace(
            "Data Memory (0x0001_0000)",
            "Data Memory (0x0001_0000–0x0002_FFFF)"
        )
        total += 1

# IP_Inventory – Data Memory note
ws_inv = wb["IP_Inventory"]
for row in ws_inv.iter_rows():
    if row[0].value and "Data Memory" in str(row[0].value):
        nc = row[7]  # Notes column (index 7)
        if nc.value:
            old = str(nc.value)
            new = old.replace(
                "Placeholder @ 0x0001_0000 in existing interconnect.",
                "Placeholder @ 0x0001_0000–0x0002_FFFF (128 KB) in existing interconnect."
            )
            if new != old:
                nc.value = new
                total += 1
        break

# Integration_Architecture – Data Memory size in decode table
ws_arch = wb["Integration_Architecture"]
for row in ws_arch.iter_rows():
    cell = row[0]
    if cell.value is None:
        continue
    v = str(cell.value)
    # Decode table line for M01 Data Memory – "64 KB" → "128 KB"
    if "M01" in v and "Data Memory" in v and "64 KB" in v:
        cell.value = v.replace("64 KB", "128 KB", 1)
        total += 1
        print("   Integration_Architecture: Data Memory decode table size → 128 KB")

# Integration_Architecture – address labels in ASCII art
for row in ws_arch.iter_rows():
    cell = row[0]
    if cell.value is None:
        continue
    v = str(cell.value)
    old_art = "[0x0000] [0x0001][0x0002][0x000D][0x000E][0x000F][0x0010][0x000A+]"
    new_art = "[0x0000] [0x0001][0x0003][0x000E][0x000F][0x0010][0x0011][0x000B+]"
    if old_art in v:
        cell.value = v.replace(old_art, new_art)
        total += 1
        print("   Integration_Architecture: ASCII art address labels updated")

# ── Step 5: Save ─────────────────────────────────────────────────────────────
wb.save(XLSX)
print(f"\nTotal changes: {total}")
print(f"Saved: {XLSX}")
