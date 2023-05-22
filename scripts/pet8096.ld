MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
    ram (rw) : ORIGIN = 0x200, LENGTH = 0xfd00
	reloram (rw) : ORIGIN = 0x3ff, LENGTH = 0x7c00
	initram (rw) : ORIGIN = 0x7000, LENGTH = 0x1000
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
		*(header)
	} >reloram

	.init : {
		init_exec_addr = .;
		init_load_addr = LOADADDR(.init);
		*(.init .init.*)
		*loader.o(.text .text.*)
		init_end_addr = .;
	} >initram AT>reloram

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
		__TPA_START__ = .;
		__TPA_END__ = 0xff00;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(reloram)
}

