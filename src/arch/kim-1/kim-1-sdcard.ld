MEMORY {
    zp : ORIGIN = 0x00, LENGTH = 0xef
    ram (rw) : ORIGIN = 0x6000, LENGTH = 0x4000
	reloram (rw) : ORIGIN = 0x400, LENGTH = 0x1000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xef;
	} >zp

	.loader : {
		*(loader)
        *loader.o(.text .text.*)
		. = ALIGN(256);
	} >ram

	.text : {
		__bios_data_start = LOADADDR(.text);
		__bios_data_end = __bios_data_start + __bios_end - __bios_start;
		__bios_start = .;
		*(.text .text.*)
	} >reloram AT>ram

	.data : {
		*(.data .data.* .rodata .rodata.*)
		__bios_end = .;
	} >reloram AT>ram

	.bss (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
		. = ALIGN(256);
	} >reloram
}

OUTPUT_FORMAT {
	TRIM(ram)
}

__TPA_START__ = 0x2000;
__TPA_END__   = 0xa000;
DISK_BUFFER   = 0x0200;
