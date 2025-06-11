MEMORY {
    ram (rw) : ORIGIN = 0x7ff, LENGTH = 0x1000
    zp : ORIGIN = 2, LENGTH = 0x8e

	drive (rw) : ORIGIN = 0x300, LENGTH = 0x300
	bootstrap (rw) : ORIGIN = 0x6000, LENGTH = 0x2000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)

		. = 0x80;
		*(.loaderzp)
	} >zp

	.text : {
		*(.text .text.*)
	} >ram
	.data : {
		 . = ALIGN(16);
		 *(.aligned.16)
		 *(.data .data.* .rodata .rodata.*)
	} > ram
	.drive : {
		drive_exec_addr = .;
		drive_load_addr = LOADADDR(.drive);
		*(.drive)
		. = ALIGN(., 32);
		drive_end_addr = .;
	} >drive AT>ram

	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
	} >ram

	.noinit (NOLOAD) : {
		bootstrap_start = .;
	} >bootstrap
}

OUTPUT_FORMAT {
	TRIM(ram)
}

