MEMORY {
    zp : ORIGIN = 0, LENGTH = 0xff
	lowram (rw) : ORIGIN = 0x200, LENGTH = 0xe00
    ram (rw) : ORIGIN = 0x2000, LENGTH = 0x6000
	init (rw) : ORIGIN = 0x7000, LENGTH = 0x1000
	block5 (rw) : ORIGIN = 0xa000, LENGTH = 0x2000
}

SECTIONS {
	__TPA_START__ = 0x2000;
	__TPA_END__ = 0x8000;
	__HIGHTPA_START__ = 0xa000;
	__HIGHTPA_END__ = 0xc000;

	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xff;

		. = 0xf0;
		*(.loaderzp)
	} >zp

	.init : {
		*(.start)
		init_exec_addr = .;
		init_load_addr = LOADADDR(.init);
		*(.init .init.*)
		*loader.o(.text .text.*)
		init_end_addr = .;
	} >init

	.text : {
		bios_exec_addr = .;
		bios_load_addr = LOADADDR(.text);
		*(.text .text.*)
	} >lowram AT>init

	.data : {
		. = ALIGN(16);
		*(.align.16)
		*(.data .data.* .rodata .rodata.*)
		bios_end_addr = .;
	} >lowram AT>init

	.noinit (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
	} >lowram
}

OUTPUT_FORMAT {
	TRIM(init)
}

