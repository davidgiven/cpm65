MEMORY {
    zp : ORIGIN = 2, LENGTH = 0x8e
    ram (rw) : ORIGIN = 0x400, LENGTH = 0x8000
	basic (rw) : ORIGIN = 0x11ff, LENGTH = 0x3000
	init (rw) : ORIGIN = 0x7000, LENGTH = 0x1000
	block5 (rw) : ORIGIN = 0xa000, LENGTH = 0x2000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0xff;
	} >zp

	.head : {
		*(header)
	} >basic

	.init : {
		init_exec_addr = .;
		init_load_addr = LOADADDR(.init);
		*(init)
		init_end_addr = .;
	} >init AT>basic

	.text : {
		bios_exec_addr = .;
		bios_load_addr = LOADADDR(.text);
		*(.text .text.*)
	} >block5 AT>basic

	.data : {
		*(.data .data.* .rodata .rodata.*)
		bios_end_addr = .;
	} >block5 AT>basic

	.noinit (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
		. = ALIGN(256);
		bios_size = . - bios_exec_addr;
		__TPA_START__ = .;
		__TPA_END__ = 0x8000;
	} >block5
}

OUTPUT_FORMAT {
	TRIM(basic)
}

