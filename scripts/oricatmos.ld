MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
    loram (rw) : ORIGIN = 0x400, LENGTH = 0xb100
	hiram (rw) : ORIGIN = 0xc000, LENGTH = 0x4000
	initram (rw) : ORIGIN = 0x400, LENGTH = 0xb000
	charset (rw) : ORIGIN = 0xb500, LENGTH = 0x300
	midram (rw) : ORIGIN = 0xb800, LENGTH = 0x380
	screen (rw) : ORIGIN = 0xbb80, LENGTH = 0x460

	jasminboot (rw) : ORIGIN = 0x0400, LENGTH = 0x0100
	microdiscboot (rw) : ORIGIN = 0x9800, LENGTH = 0x0200
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xff;

		. = 0xf0;
		*(.loaderzp)
	} >zp

	.head : {
		*(sector1) 
		. = ALIGN(256);
	} >jasminboot AT>initram

	.head : {
		*(sector2) 
		. = ALIGN(256);
		*(sector3)
		. = ALIGN(256);
	} >microdiscboot AT>initram

	.text : {
		bios_exec_addr = .;
		 *(.text .text.*)
	 } >hiram AT>initram

	.data : {
		*(.data .data.* .rodata .rodata.*)
	} > hiram AT>initram

	.noinit (NOLOAD) : { *(.noinit .noinit.*) } >hiram
}

OUTPUT_FORMAT {
	TRIM(initram)
}

