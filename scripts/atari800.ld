MEMORY {
    zp : ORIGIN = 0x80, LENGTH = 0x7f
    ram (rw) : ORIGIN = 0x500, LENGTH = 0x800
    midram(rw) : ORIGIN = 0x3000, LENGTH = 0x800
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
    } >midram

	.text : {
        bios_exec_addr = .;
        bios_load_addr = LOADADDR(.text);
		*(.text .text.*)
	} >ram AT>midram

	.data : {
        *(.data .data.* .rodata .rodata.*)
        bios_end_addr = .;
    } >ram AT>midram

	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__SCREENDATA_START__ = .;
		__USERTPA_START__ = .+0x400;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(midram)
}

