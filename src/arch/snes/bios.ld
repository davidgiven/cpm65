MEMORY {
    zp : ORIGIN = 0, LENGTH = 0x100
    ram (rw) : ORIGIN = 0x200, LENGTH = 0xfd00
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0xff;
	} >zp

	.text : { *(.text .text.*) } >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : { *(.noinit .noinit.*) } >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

