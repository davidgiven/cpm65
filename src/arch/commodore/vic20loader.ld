MEMORY {
    ram (rw) : ORIGIN = 0x7ff, LENGTH = 0x1000
    zp : ORIGIN = 2, LENGTH = 0x8e
	basic (rw) : ORIGIN = 0x11ff, LENGTH = 0x3000
	bootstrap (rw) : ORIGIN = 0x7000, LENGTH = 0x1000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)

		. = 0x80;
		*(.loaderzp)
	} >zp

	.text : {
		*(.text .text.*)
	} >basic
	.data : {
		 . = ALIGN(32);
		 *(.aligned.32)
		 *(.data .data.* .rodata .rodata.*)
	} > basic
	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
	} >basic

	.noinit (NOLOAD) : {
		bootstrap_start = .;
	} >bootstrap
}

OUTPUT_FORMAT {
	TRIM(basic)
}

