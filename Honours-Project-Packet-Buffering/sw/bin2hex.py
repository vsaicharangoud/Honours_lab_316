#!/usr/bin/env python3
"""
bin2hex.py  –  Convert a raw binary to Verilog $readmemh word-addressed hex.

Usage:
    python3 bin2hex.py <input.bin> <output.hex>

The output format is:
    @00000000
    XXXXXXXX
    XXXXXXXX
    ...

where each line is one 32-bit word in hex (little-endian byte order from the binary).
This matches what Verilog $readmemh expects when loading into a reg[31:0] array.
"""
import sys
import struct

def bin_to_hex(in_path, out_path):
    with open(in_path, 'rb') as f:
        data = f.read()

    # Pad to 4-byte boundary
    remainder = len(data) % 4
    if remainder:
        data += b'\x00' * (4 - remainder)

    num_words = len(data) // 4
    words = struct.unpack('<' + 'I' * num_words, data)

    with open(out_path, 'w') as f:
        f.write('@00000000\n')
        for w in words:
            f.write('%08X\n' % w)

    print('[bin2hex] %s -> %s  (%d words, %d bytes)' % (
        in_path, out_path, num_words, len(data)))

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: bin2hex.py <input.bin> <output.hex>', file=sys.stderr)
        sys.exit(1)
    bin_to_hex(sys.argv[1], sys.argv[2])
