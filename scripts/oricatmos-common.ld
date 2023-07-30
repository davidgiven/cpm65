 /* Common part of the Oric loader script. This generates the BIOS proper, at the
  * top of RAM. */

BIOS_SIZE_ROUNDED_UP = (BIOS_SIZE + 255) & 0xff00;
BIOS_PADDING = BIOS_SIZE_ROUNDED_UP - BIOS_SIZE;

.bss (0x10000-BIOS_SIZE_ROUNDED_UP) (NOLOAD) : {
    . = ALIGN(256) + BIOS_PADDING;
    *(.bss .bss.*)
    *(.noinit .noinit.*)
} >hiram AT>initram

.data : {
    bios_data_start = .;
    *(.data .data.* .rodata .rodata.*)
} >hiram AT>initram

.text : {
    *(.text .text.*) 
    *(tail)
} >hiram AT>initram

.dummy : {
    BIOS_SECTOR_COUNT = ((0x10000 - bios_data_start) + 255) / 256;
    BIOS_LOAD_ADDR = 0x10000 - BIOS_SECTOR_COUNT*256;
} AT>initram
