#!/usr/bin/python3

import sys
import os

bootsector_size = 512
bdos_offset = 512*256
cpmfs_offset = 512*256
cpmfs_size = 1024*1024

bios_filename = '.obj/src/arch/nano6502/+nano6502/+nano6502'
bdos_filename = '.obj/src/bdos/+bdos/+bdos'
cpmfs_filename = '.obj/src/arch/nano6502/+cpmfs/src/arch/nano6502/+cpmfs.img'
cpmfs_empty_filename = '.obj/src/arch/nano6502/+emptycpmfs/src/arch/nano6502/+emptycpmfs.img'
output_filename = '.obj/src/arch/nano6502/+sysimage/nano6502_sysonly.img'

size = os.path.getsize(bios_filename)

outfile=open(output_filename, "wb")

# Write boot sector
# Boot sector format
# Magic number: 0x6E, 0x61, 0x6E, 0x6F
# SD sector to load - 4 bytes
# Number of pages to load - 1 byte
# Page to load data to - 1 byte
# Total 10 bytes
# Padding 502 bytes

bootsector_data = [0x6E, 0x61, 0x6E, 0x6F, 0x00, 0x00, 0x00, 0x01, 0x04, 0x03]

for d in bootsector_data:
    outfile.write(d.to_bytes(1, "little"))

out=0
for i in range(bootsector_size - len(bootsector_data)):
    outfile.write(out.to_bytes(1, "little"))
   
# Write BIOS

infile=open(bios_filename, "rb")
byte=infile.read(1)

# Write BIOS
while byte:
    outfile.write(byte)
    byte=infile.read(1)

padding = bdos_offset - size - bootsector_size
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

padding = cpmfs_size - size;
out=0
while padding:
    outfile.write(out.to_bytes(1,"little"))
    padding = padding - 1;

infile.close()
outfile.close()
