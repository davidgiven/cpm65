/*
 * Ohio Scientific Instruments Linker Script
 */

MEMORY {
    zp : ORIGIN = 0x00, LENGTH = 0xff
    ram (rw) : ORIGIN = 0x0200, LENGTH = 0x9e00
    loader(rw) : ORIGIN = 0x2200, LENGTH = 0x0800
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0xff;

        . = 0xf0;
        *(.loaderzp)
	} >zp

    .loader : {
        *(loader)
        *loader.o(.text .text.*)
    } >loader

	.text : {
        bios_exec_addr = .;
        bios_load_addr = LOADADDR(.text);
		*(.text .text.*)
	} >ram AT>loader

	.data : {
        *(.data .data.* .rodata .rodata.*)
        bios_end_addr = .;
    } >ram AT>loader

	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__USERTPA_START__ = .;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(loader)
}
