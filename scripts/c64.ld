MEMORY {
    zp : ORIGIN = 2, LENGTH = 0x8e
    ram (rw) : ORIGIN = 0x7ff, LENGTH = 0x800
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0x8e;
	} >zp

	.text : {
		*(.text .text.*)
	} >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__USERTPA_START__ = .;
		__USERTPA_END__ = 0xd000;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

