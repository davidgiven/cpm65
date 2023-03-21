BDOS system calls: https://www.seasip.info/Cpm/bdos.html
Point to the BDOS entrypoint is passed to the application at header+4 (after a
JMP instruction, so making the entrypoint JSRable). Pass the function code in Y
and the parameter in XA. C is set on error.

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
38: get BDOS entrypoint
40: write random with zero fill

BIOS system calls: https://www.seasip.info/Cpm/bios.html The entrypoint can be
fetched with BDOS call 38 (which is new).  Call with the function code in Y and
the parameter in XA. C is set on error.

0: CONST: console status
1: CONIN: console input
2: CONOUT: console output
3: SELDSK: select disk drive
4: SETSEC: select sector (parameter is a _pointer_ to a 24-bit number)
5: SETDMA: set DMA address
6: READ: read a sector
7: WRITE: write a sector
8: RELOCATE: relocate a binary
9: GETTPA: get TPA bounds
10: SETTPA: set TPA bounds
11: GETZP: get ZP bounds
12: SETZP: set ZP bounds

Executable format:

byte 0000 number of zero page bytes required
byte 0001 number of TPA memory pages required
word 0002 offset of relocation table
byte 0004 must be $4c
word 0005 address of BDOS entrypoint
code 0007 entrypoint
...

Relocation bytes: two strings of nibbles, in MSB/LSB order, representing
incremental offsets from the beginning of the file; 0xe advances pointer but
does nothing and 0xf terminates the stream (any trailing 0 is ignored). The
first one is for ZP, second is for high byte of any addresses.

**Important!** The relocation table address at offset 2 must, itself, be
relocated --- the CCP uses this to locate the program's pblock.

Once relocated, the address which the relocation table is at is repurposed as
the pblock, a 165-byte structure which contains the initial FCBs and command
line:

byte 0000 first FCB start
byte 0010 second FCB start (only the filename bytes are usable)
byte 0025 default DMA address
byte 0025 ...also, command line length
byte 0026 127 bytes of command line

The binary's BSS must start above this (if you want to use it, which you don't
have to).

