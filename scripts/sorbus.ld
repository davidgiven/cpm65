MEMORY {
    zp : ORIGIN = 4, LENGTH = 0xfe
    ram (rw) : ORIGIN = 0xe000, LENGTH = 0x0800
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0xe0;

		. = 0xe0;
		*(.loaderzp)
	} >zp

	.text : {
		*(.text .text.*)
	} >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__USERTPA_START__ = .;
		__USERTPA_END__ = 0xe800;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

