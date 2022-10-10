MEMORY {
    zp : ORIGIN = 0, LENGTH = 0x90
    ram (rw) : ORIGIN = 0x400, LENGTH = 0x400
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0x90;
	} >zp

	.text : { *(.text .text.*) } >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : { *(.noinit .noinit.*) } >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

