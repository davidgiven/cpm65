MEMORY {
    zp : ORIGIN = 0x00, LENGTH = 0xef
    ram (rw) : ORIGIN = 0x2000, LENGTH = 0xde00
	reloram (rw) : ORIGIN = 0x200, LENGTH = 0x1200
    usrram (rw) : ORIGIN = 0xc000, LENGTH = 0x2000
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
		*libsd.o(.init .init.*)
		. = ALIGN(256);
	} >usrram

	.text : {
		__bios_data_start = LOADADDR(.text);
		__bios_data_end = __bios_data_start + __bios_end - __bios_start;
		__bios_start = .;
		*(.text .text.*)
		. = ALIGN(256);
	} >reloram AT>usrram

	.data : {
		*(.data .data.* .rodata .rodata.*)
		__bios_end = .;
		. = ALIGN(256);
	} >reloram AT>usrram

	.noinit (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
		. = ALIGN(256);
	} >reloram
}

OUTPUT_FORMAT {
	TRIM(usrram)
}

__TPA_START__ = 0x2000;
__TPA_END__   = 0xfe00;
DISK_BUFFER = __TPA_END__;

