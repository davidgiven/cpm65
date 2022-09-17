ffe0 system call entrypoints
f800 I/O ports
c000 kernel ROM
8000 application ROM
.... video memory
7c00 HIMEM
     CCP
     ....
     TPA
     BDOS
1900 PAGE
....
0800 filesystem storage
0400 language workspace
0200 OS gubbins
0100 stack
0000 zero page


BDOS system calls: https://www.seasip.info/Cpm/bdos.html

0: exit program
1: console input
2: console output
3: aux input
4: aux output
5: printer output
6: direct console I/O
7: get I/O byte
8: set I/O byte
9: write string, $ terminated
10: buffered console input
11: console status
12: get version
13: reset disks
14: select disk
15: open file
16: close file
17: find first
18: find next
19: delete file
20: read next record
21: write next record
22: create and open file
23: rename file
24: return login bitmap
25: get current drive
26: set DMA address
27: get allocation bitmap address
28: set drive read-only
29: get read-only drive bitmap
30: set file attributes
31: get DPB address
32: get/set user number
33: random access read
34: random access write
35: compute file size
36: compute random access pointer
37: reset some drives
40: write random with zero fill

BIOS system calls: https://www.seasip.info/Cpm/bios.html

BOOT: cold start
WBOOT: warm start
CONST: console status
CONIN: console input
CONOUT: console output
SELDSK: select disk drive
SETTRK: select track
SETSEC: select sector
SETDMA: set DMA address
READ: read a sector
WRITE: write a sector
RELOCATE: relocate a binary
GETTPA: get TPA bounds
SETTPA: set TPA bounds
GETZP: get ZP bounds
SETZP: set ZP bounds

Executable format:

byte 0000 number of zero page bytes required
word 0001 offset of relocation table
code 0003 JMP instruction to BDOS (only COM files)
code 0006 entrypoint
...
relocation bytes: two zero-terminated strings of incremental offsets from the
beginning of the file; 0xff advances pointer but does nothing; first one is for
ZP, second is for high byte of memory
