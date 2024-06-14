#!/usr/bin/python3

import sys
import os

bdos_offset = 512*256
cpmfs_offset = 512*256*2

bios_filename = '.obj/src/arch/nano6502/+nano6502/+nano6502'
bdos_filename = '.obj/src/bdos/+bdos/+bdos'
cpmfs_filename = '.obj/src/arch/nano6502/+cpmfs/src/arch/nano6502/+cpmfs.img'

output_filename = './nano6502.img'

size = os.path.getsize(bios_filename)

infile=open(bios_filename, "rb")
outfile=open(output_filename, "wb")

byte=infile.read(1)
# Write BIOS
while byte:
    outfile.write(byte)
    byte=infile.read(1)

padding = bdos_offset - size;
out = 0

while padding:
    outfile.write(out.to_bytes(1,"little"))
    padding = padding - 1;

infile.close()

# Write BDOS
size = os.path.getsize(bdos_filename)

infile = open(bdos_filename, "rb")

byte=infile.read(1)
while byte:
    outfile.write(byte)
    byte=infile.read(1)

padding = cpmfs_offset - size;
out = 0

while padding:
    outfile.write(out.to_bytes(1,"little"))
    padding = padding - 1;

infile.close()

# Write CPMFS
size = os.path.getsize(cpmfs_filename)

infile = open(cpmfs_filename, "rb")

byte=infile.read(1)
while byte:
    outfile.write(byte)
    byte=infile.read(1)

infile.close()
outfile.close()
