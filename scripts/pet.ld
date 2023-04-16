MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
    ram (rw) : ORIGIN = 0x200, LENGTH = 0x7e00
	reloram (rw) : ORIGIN = 0x3ff, LENGTH = 0x7c00
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0x90;
	} >zp

	head : {
		*(header)
	} >reloram

	.text : {
		bios_exec_addr = .;
		bios_load_addr = LOADADDR(.text);
		*(.text .text.*)
	} >ram AT>reloram

	.data : {
		*(.data .data.* .rodata .rodata.*)
		bios_end_addr = .;
	} >ram AT>reloram

	.noinit (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
		. = ALIGN(256);
		bios_size = . - bios_exec_addr;
		__USERTPA_START__ = .;
		__USERTPA_END__ = 0x8000;
	} >ram

	tail : {
		*(relocator)
	} >reloram
}

OUTPUT_FORMAT {
	TRIM(reloram)
}

