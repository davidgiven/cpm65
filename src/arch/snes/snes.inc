; Address Bus B Registers
INIDISP    equ 0x2100   ;   Screen Display Register   single   write   any time
OBSEL      equ 0x2101   ;   Object Size and Character Size Register   single   write   f-blank, v-blank
OAMADDL    equ 0x2102   ;   OAM Address Registers (Low)   single   write   f-blank, v-blank
OAMADDH    equ 0x2103   ;   OAM Address Registers (High)   single   write   f-blank, v-blank
OAMDATA    equ 0x2104   ;   OAM Data Write Register   single   write   f-blank, v-blank
BGMODE     equ 0x2105   ;   BG Mode and Character Size Register   single   write   f-blank, v-blank, h-blank
MOSAIC     equ 0x2106   ;   Mosaic Register   single   write   f-blank, v-blank, h-blank
BG1SC      equ 0x2107   ;   BG Tilemap Address Registers (BG1)   single   write   f-blank, v-blank
BG2SC      equ 0x2108   ;   BG Tilemap Address Registers (BG2)   single   write   f-blank, v-blank
BG3SC      equ 0x2109   ;   BG Tilemap Address Registers (BG3)   single   write   f-blank, v-blank
BG4SC      equ 0x210A   ;   BG Tilemap Address Registers (BG4)   single   write   f-blank, v-blank
BG12NBA    equ 0x210B   ;   BG Character Address Registers (BG1&2)   single   write   f-blank, v-blank
BG34NBA    equ 0x210C   ;   BG Character Address Registers (BG3&4)   single   write   f-blank, v-blank
BG1HOFS    equ 0x210D   ;   BG Scroll Registers (BG1)   dual   write   f-blank, v-blank, h-blank
BG1VOFS    equ 0x210E   ;   BG Scroll Registers (BG1)   dual   write   f-blank, v-blank, h-blank
BG2HOFS    equ 0x210F   ;   BG Scroll Registers (BG2)   dual   write   f-blank, v-blank, h-blank
BG2VOFS    equ 0x2110   ;   BG Scroll Registers (BG2)   dual   write   f-blank, v-blank, h-blank
BG3HOFS    equ 0x2111   ;   BG Scroll Registers (BG3)   dual   write   f-blank, v-blank, h-blank
BG3VOFS    equ 0x2112   ;   BG Scroll Registers (BG3)   dual   write   f-blank, v-blank, h-blank
BG4HOFS    equ 0x2113   ;   BG Scroll Registers (BG4)   dual   write   f-blank, v-blank, h-blank
BG4VOFS    equ 0x2114   ;   BG Scroll Registers (BG4)   dual   write   f-blank, v-blank, h-blank
VMAIN      equ 0x2115   ;   Video Port Control Register   single   write   f-blank, v-blank
VMADDL     equ 0x2116   ;   VRAM Address Registers (Low)   single   write   f-blank, v-blank
VMADDH     equ 0x2117   ;   VRAM Address Registers (High)   single   write   f-blank, v-blank
VMDATAL    equ 0x2118   ;   VRAM Data Write Registers (Low)   single   write   f-blank, v-blank
VMDATAH    equ 0x2119   ;   VRAM Data Write Registers (High)   single   write   f-blank, v-blank
M7SEL      equ 0x211A   ;   Mode 7 Settings Register   single   write   f-blank, v-blank
M7A        equ 0x211B   ;   Mode 7 Matrix Registers   dual   write   f-blank, v-blank, h-blank
M7B        equ 0x211C   ;   Mode 7 Matrix Registers   dual   write   f-blank, v-blank, h-blank
M7C        equ 0x211D   ;   Mode 7 Matrix Registers   dual   write   f-blank, v-blank, h-blank
M7D        equ 0x211E   ;   Mode 7 Matrix Registers   dual   write   f-blank, v-blank, h-blank
M7X        equ 0x211F   ;   Mode 7 Matrix Registers   dual   write   f-blank, v-blank, h-blank
M7Y        equ 0x2120   ;   Mode 7 Matrix Registers   dual   write   f-blank, v-blank, h-blank
CGADD      equ 0x2121   ;   CGRAM Address Register   single   write   f-blank, v-blank, h-blank
CGDATA     equ 0x2122   ;   CGRAM Data Write Register   dual   write   f-blank, v-blank, h-blank
W12SEL     equ 0x2123   ;   Window Mask Settings Registers   single   write   f-blank, v-blank, h-blank
W34SEL     equ 0x2124   ;   Window Mask Settings Registers   single   write   f-blank, v-blank, h-blank
WOBJSEL    equ 0x2125   ;   Window Mask Settings Registers   single   write   f-blank, v-blank, h-blank
WH0        equ 0x2126   ;   Window Position Registers (WH0)   single   write   f-blank, v-blank, h-blank
WH1        equ 0x2127   ;   Window Position Registers (WH1)   single   write   f-blank, v-blank, h-blank
WH2        equ 0x2128   ;   Window Position Registers (WH2)   single   write   f-blank, v-blank, h-blank
WH3        equ 0x2129   ;   Window Position Registers (WH3)   single   write   f-blank, v-blank, h-blank
WBGLOG     equ 0x212A   ;   Window Mask Logic registers (BG)   single   write   f-blank, v-blank, h-blank
WOBJLOG    equ 0x212B   ;   Window Mask Logic registers (OBJ)   single   write   f-blank, v-blank, h-blank
TM         equ 0x212C   ;   Screen Destination Registers   single   write   f-blank, v-blank, h-blank
TS         equ 0x212D   ;   Screen Destination Registers   single   write   f-blank, v-blank, h-blank
TMW        equ 0x212E   ;   Window Mask Destination Registers   single   write   f-blank, v-blank, h-blank
TSW        equ 0x212F   ;   Window Mask Destination Registers   single   write   f-blank, v-blank, h-blank
CGWSEL     equ 0x2130   ;   Color Math Registers   single   write   f-blank, v-blank, h-blank
CGADSUB    equ 0x2131   ;   Color Math Registers   single   write   f-blank, v-blank, h-blank
COLDATA    equ 0x2132   ;   Color Math Registers   single   write   f-blank, v-blank, h-blank
SETINI     equ 0x2133   ;   Screen Mode Select Register   single   write   f-blank, v-blank, h-blank
MPYL       equ 0x2134   ;   Multiplication Result Registers   single   read   f-blank, v-blank, h-blank
MPYM       equ 0x2135   ;   Multiplication Result Registers   single   read   f-blank, v-blank, h-blank
MPYH       equ 0x2136   ;   Multiplication Result Registers   single   read   f-blank, v-blank, h-blank
SLHV       equ 0x2137   ;   Software Latch Register   single      any time
OAMDATAREAD equ 0x2138   ;   OAM Data Read Register   dual   read   f-blank, v-blank
VMDATALREAD equ 0x2139   ;   VRAM Data Read Register (Low)   single   read   f-blank, v-blank
VMDATAHREAD equ 0x213A   ;   VRAM Data Read Register (High)   single   read   f-blank, v-blank
CGDATAREAD equ 0x213B   ;   CGRAM Data Read Register   dual   read   f-blank, v-blank
OPHCT      equ 0x213C   ;   Scanline Location Registers (Horizontal)   dual   read   any time
OPVCT      equ 0x213D   ;   Scanline Location Registers (Vertical)   dual   read   any time
STAT77     equ 0x213E   ;   PPU Status Register   single   read   any time
STAT78     equ 0x213F   ;   PPU Status Register   single   read   any time
APUIO0     equ 0x2140   ;   APU IO Registers   single   both   any time
APUIO1     equ 0x2141   ;   APU IO Registers   single   both   any time
APUIO2     equ 0x2142   ;   APU IO Registers   single   both   any time
APUIO3     equ 0x2143   ;   APU IO Registers   single   both   any time
WMDATA     equ 0x2180   ;   WRAM Data Register   single   both   any time
WMADDL     equ 0x2181   ;   WRAM Address Registers   single   write   any time
WMADDM     equ 0x2182   ;   WRAM Address Registers   single   write   any time
WMADDH     equ 0x2183   ;   WRAM Address Registers   single   write   any time

; Old Style Joypad Registers
JOYSER0    equ 0x4016   ;   Old Style Joypad Registers   single (write)   read/write   any time that is not auto-joypad
JOYSER1    equ 0x4017   ;   Old Style Joypad Registers   many (read)   read   any time that is not auto-joypad

; Internal CPU Registers
NMITIMEN   equ 0x4200   ;   Interrupt Enable Register   single   write   any time
WRIO       equ 0x4201   ;   IO Port Write Register   single   write   any time
WRMPYA     equ 0x4202   ;   Multiplicand Registers   single   write   any time
WRMPYB     equ 0x4203   ;   Multiplicand Registers   single   write   any time
WRDIVL     equ 0x4204   ;   Divisor & Dividend Registers   single   write   any time
WRDIVH     equ 0x4205   ;   Divisor & Dividend Registers   single   write   any time
WRDIVB     equ 0x4206   ;   Divisor & Dividend Registers   single   write   any time
HTIMEL     equ 0x4207   ;   IRQ Timer Registers (Horizontal - Low)   single   write   any time
HTIMEH     equ 0x4208   ;   IRQ Timer Registers (Horizontal - High)   single   write   any time
VTIMEL     equ 0x4209   ;   IRQ Timer Registers (Vertical - Low)   single   write   any time
VTIMEH     equ 0x420A   ;   IRQ Timer Registers (Vertical - High)   single   write   any time
MDMAEN     equ 0x420B   ;   DMA Enable Register   single   write   any time
HDMAEN     equ 0x420C   ;   HDMA Enable Register   single   write   any time
MEMSEL     equ 0x420D   ;   ROM Speed Register   single   write   any time
RDNMI      equ 0x4210   ;   Interrupt Flag Registers   single   read   any time
TIMEUP     equ 0x4211   ;   Interrupt Flag Registers   single   read   any time
HVBJOY     equ 0x4212   ;   PPU Status Register   single   read   any time
RDIO       equ 0x4213   ;   IO Port Read Register   single   read   any time
RDDIVL     equ 0x4214   ;   Multiplication Or Divide Result Registers (Low)   single   read   any time
RDDIVH     equ 0x4215   ;   Multiplication Or Divide Result Registers (High)   single   read   any time
RDMPYL     equ 0x4216   ;   Multiplication Or Divide Result Registers (Low)   single   read   any time
RDMPYH     equ 0x4217   ;   Multiplication Or Divide Result Registers (High)   single   read   any time
JOY1L      equ 0x4218   ;   Controller Port Data Registers (Pad 1 - Low)   single   read   any time that is not auto-joypad
JOY1H      equ 0x4219   ;   Controller Port Data Registers (Pad 1 - High)   single   read   any time that is not auto-joypad
JOY2L      equ 0x421A   ;   Controller Port Data Registers (Pad 2 - Low)   single   read   any time that is not auto-joypad
JOY2H      equ 0x421B   ;   Controller Port Data Registers (Pad 2 - High)   single   read   any time that is not auto-joypad
JOY3L      equ 0x421C   ;   Controller Port Data Registers (Pad 3 - Low)   single   read   any time that is not auto-joypad
JOY3H      equ 0x421D   ;   Controller Port Data Registers (Pad 3 - High)   single   read   any time that is not auto-joypad
JOY4L      equ 0x421E   ;   Controller Port Data Registers (Pad 4 - Low)   single   read   any time that is not auto-joypad
JOY4H      equ 0x421F   ;   Controller Port Data Registers (Pad 4 - High)   single   read   any time that is not auto-joypad

; DMA/HDMA Registers
DMAPx      equ 0x4300   ;   (H)DMA Control Register
BBADx      equ 0x4301   ;   (H)DMA Destination Register
A1TxL      equ 0x4302   ;   (H)DMA Source Address Registers
A1TxH      equ 0x4303   ;   (H)DMA Source Address Registers
A1Bx       equ 0x4304   ;   (H)DMA Source Address Registers
DASxL      equ 0x4305   ;   (H)DMA Size Registers (Low)
DASxH      equ 0x4306   ;   (H)DMA Size Registers (High)
DASBx      equ 0x4307   ;   HDMA Indirect Address Registers
A2AxL      equ 0x4308   ;   HDMA Mid Frame Table Address Registers (Low)
A2AxH      equ 0x4309   ;   HDMA Mid Frame Table Address Registers (High)
NTLRx      equ 0x430A   ;   HDMA Line Counter Register
