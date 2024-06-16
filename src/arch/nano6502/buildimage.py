#!/usr/bin/python3

import sys
import os

bdos_offset = 512*256
cpmfs_offset = 512*256
cpmfs_size = 1024*1024

bios_filename = '.obj/src/arch/nano6502/+nano6502/+nano6502'
bdos_filename = '.obj/src/bdos/+bdos/+bdos'
cpmfs_filename = '.obj/src/arch/nano6502/+cpmfs/src/arch/nano6502/+cpmfs.img'
cpmfs_empty_filename = '.obj/src/arch/nano6502/+emptycpmfs/src/arch/nano6502/+emptycpmfs.img'
output_filename = './nano6502.img'
output_sysonly_filename = './nano6502_sysonly.img'

size = os.path.getsize(bios_filename)

infile=open(bios_filename, "rb")
outfile=open(output_filename, "wb")
sysfile=open(output_sysonly_filename, "wb")

byte=infile.read(1)
# Write BIOS
while byte:
    outfile.write(byte)
    sysfile.write(byte)
    byte=infile.read(1)

padding = bdos_offset - size;
out = 0

while padding:
    outfile.write(out.to_bytes(1,"little"))
    sysfile.write(out.to_bytes(1,"little"))
    padding = padding - 1;

infile.close()

# Write BDOS
size = os.path.getsize(bdos_filename)

infile = open(bdos_filename, "rb")

byte=infile.read(1)
while byte:
    outfile.write(byte)
    sysfile.write(byte)
    byte=infile.read(1)

padding = cpmfs_offset - size;
out = 0

while padding:
    outfile.write(out.to_bytes(1,"little"))
    sysfile.write(out.to_bytes(1,"little"))
    padding = padding - 1;

infile.close()

# Write CPMFS
size = os.path.getsize(cpmfs_filename)

infile = open(cpmfs_filename, "rb")

byte=infile.read(1)
while byte:
    outfile.write(byte)
    sysfile.write(byte)
    byte=infile.read(1)

padding = cpmfs_size - size;
out=0
while padding:
    outfile.write(out.to_bytes(1,"little"))
    sysfile.write(out.to_bytes(1,"little"))
    padding = padding - 1;

infile.close()
sysfile.close()

# Write empty drives B-O
for i in range(15):
    size = os.path.getsize(cpmfs_empty_filename)

    infile = open(cpmfs_empty_filename, "rb")

    byte=infile.read(1)
    while byte:
        outfile.write(byte)
        byte=infile.read(1)

    padding = cpmfs_size - size;
    out=0
    while padding:
        outfile.write(out.to_bytes(1,"little"))
        padding = padding - 1;

    infile.close()

outfile.close()
