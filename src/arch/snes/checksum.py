import sys

# applies the SNES checksum to a ROM
# usage:
#   checksum.py LOROM filein [fileout]
#   checksum.py HIROM filein [fileout]

def checksum(addr,filein,fileout=None):
    assert(addr >= 0)
    if fileout == None:
        fileout = filein
    rom = bytearray(open(filein,"rb").read())
    print("ROM: %s" % filein)
    print("SIZE: %dk + %d bytes" % (len(rom)//1024,len(rom)%1024))
    truncate = len(rom)
    # find power of 1 for first "half" of ROM
    rs0 = 32 * 1024
    rs1 = 0
    while (rs0 * 2) <= len(rom):
        rs0 *= 2
    if rs0 != len(rom): # second "half" of mixed size
        rs1 = 32 * 1024
        while (rs0 + (rs1 * 2)) <= len(rom):
            rs1 *= 2
        if (rs0 + rs1) != len(rom):
            print("ROM size must be sum of two powers of 2 larger than 32k!")
            sys.exit(2)
        print("SPLIT: %dk + %d bytes / %dk + %d bytes" % (rs0//1024,rs0%1024,rs1//1024,rs1%1024))
        while rs1 < rs0:
            rom.extend(rom[-rs1:])
            rs1 *= 2
        print("DUPLICATED: %dk + %d bytes" % (len(rom)//1024,len(rom)%1024))
    # erase existing checksum
    rom[addr+0] = 0x00
    rom[addr+1] = 0x00
    rom[addr+2] = 0xFF
    rom[addr+3] = 0xFF
    # compute
    cs = 0x0000
    for i in range(len(rom)):
        cs = (cs + rom[i+0]) & 0xFFFF
    print("CHECKSUM: $%04X" % cs)
    rom[addr+2] = cs & 0xFF
    rom[addr+3] = cs >> 8
    rom[addr+0] = rom[addr+2] ^ 0xFF
    rom[addr+1] = rom[addr+3] ^ 0xFF
    # verify
    cs2 = 0x0000
    for i in range(len(rom)):
        cs2 = (cs2 + rom[i+0]) & 0xFFFF
    assert(cs == cs2)   
    open(fileout,"wb").write(rom[0:truncate])
    print("SAVED: %s" % fileout)

def usage():
    print("2 or 3 arguments required: LOROM/HIROM filein [fileout]")
    sys.exit(1)

if __name__ == '__main__':
    addr = -1
    filein = None
    fileout = None
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        usage()
    if sys.argv[1].upper() == "LOROM":
        addr = 0x7FDC
    elif sys.argv[1].upper() == "HIROM":
        addr = 0xFFDC
    else:
        usage()
    filein = sys.argv[2]
    if len(sys.argv) >= 4:
        fileout = sys.argv[3]
    checksum(addr,filein,fileout)
    sys.exit(0)

