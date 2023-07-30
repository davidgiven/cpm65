 /* Common part of the Oric loader script. This generates the BIOS proper, at the
  * top of RAM. */

BIOS_SIZE_ROUNDED_UP = (BIOS_SIZE + 255) & 0xff00;
BIOS_PADDING = BIOS_SIZE_ROUNDED_UP - BIOS_SIZE;

.zp : {
    *(.zp .zp.*)
    __ZEROPAGE_START__ = .;
    __ZEROPAGE_END__ = 0xff;
} >zp

.bss (0x10000-BIOS_SIZE_ROUNDED_UP) (NOLOAD) : {
    . = . + BIOS_PADDING;
    *(.bss .bss.*)
    *(.noinit .noinit.*)
    bios_data_start = . & 0xff00;
    bios_start = .;
} >hiram

padding : {
    . = . + (bios_start - bios_data_start);
} >initram

.data : {
    *(.data .data.* .rodata .rodata.*)
} >hiram AT>initram

.text : {
    *(loader)
    *loader.o(.text .text.*)
    *(.text .text.*) 
    *(tail)
} >hiram AT>initram

.dummy : {
    BIOS_SECTOR_COUNT = (0x10000 - bios_data_start) / 256;
    BIOS_LOAD_ADDR = 0x10000 - BIOS_SECTOR_COUNT*256;
} AT>initram

__TPA0_START__ = 0x0400;
__TPA0_END__ = 0xb500;

__TPA1_START__ = 0xc000;
__TPA1_END__ = ADDR(.bss);

DISK_BUFFER = 0x0200;
