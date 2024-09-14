MEMORY {
    zp : ORIGIN = 0x10, LENGTH = 0xf0
    ram (rw) : ORIGIN = 0x0300, LENGTH = 0x0F00
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xff;
	} >zp

	.text : { *(.text .text.*) } >ram
	.data : { *(.data .data.* .rodata .rodata.*) } > ram
	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__TPA0_START__ = .;
		__TPA0_END__   = 0xFE00;

	} >ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

