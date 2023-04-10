MEMORY {
    zp : ORIGIN = 0, LENGTH = 0x100
    ram (rw) : ORIGIN = 0x800, LENGTH = 0x1000
	midram (rw) : ORIGIN = 0xd000, LENGTH = 0x1000
	highram (rw) : ORIGIN = 0xe000, LENGTH = 0x2000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0x100;
	} >zp

	.loader : {
		*(loader)
	} >ram

	.bss (0x10000-BIOS_SIZE) (NOLOAD) : {
		*(.bss .bss.*)
	} >highram

	.data : {
		bios_exec_addr = .;
		bios_load_addr = LOADADDR(.data);
		*(.data .data.* .rodata .rodata.*)
	} >highram AT>ram

	.text : {
		*(.text .text.*) 
		*(tail)
	} >highram AT>ram

	.dummy : {
		BIOS_SECTOR_COUNT = ((. - LOADADDR(.loader)) + 255) / 256;
	} AT>ram

	__TPA1_START__ = 0xe000;
	__TPA1_END__   = LOADADDR(.bss);

	__TPA0_START__ = 0x0800;
	__TPA0_END__   = 0xc000;
}

OUTPUT_FORMAT {
	TRIM(ram)
}


