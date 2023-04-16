MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
    ram (rw) : ORIGIN = 0x3ff, LENGTH = 0x800
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0x90;
	} >zp

	.text : {
		*(.text .text.*)
	} >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__USERTPA_START__ = .;
		__USERTPA_END__ = 0x8000;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

