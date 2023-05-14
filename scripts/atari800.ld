MEMORY {
    zp : ORIGIN = 0x80, LENGTH = 0x7e
    ram (rw) : ORIGIN = 0x700, LENGTH = 0x800
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0xfe;
	} >zp

	.text : {
		*(.text .text.*)
	} >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__USERTPA_START__ = .;
		__USERTPA_END__ = 0xbc00;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

