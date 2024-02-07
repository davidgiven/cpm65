 /* Common part of the Neo6502 loader script. This generates the BIOS proper,
  * at the top of RAM. */

BIOS_TOP = 0xff00;

.zp : {
    *(.zp .zp.*)
    __ZEROPAGE_START__ = .;
    __ZEROPAGE_END__ = 0xff;
} >zp

.loader : {
    *(loader)
    *loader.o(.text .text.*)
	BIOS_LOAD_ADDR = .;
} >initram

.bss (BIOS_TOP - BIOS_SIZE) (NOLOAD) : {
    *(.bss .bss.*)
    *(.noinit .noinit.*)
    bios_data_start = .;
} >hiram

.data : {
	BIOS_EXEC_ADDR = .;
    *(.data .data.* .rodata .rodata.*)
} >hiram AT>initram

.text : {
    *(.text .text.*) 
    *(tail)
} >hiram AT>initram

__TPA0_START__ = 0x0200;
__TPA0_END__ = ADDR(.bss);
