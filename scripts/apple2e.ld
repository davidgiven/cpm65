MEMORY {
    zp : ORIGIN = 2, LENGTH = 0xfe
    ram (rw) : ORIGIN = 0x800, LENGTH = 0x1000
	midram (rw) : ORIGIN = 0xd000, LENGTH = 0x1000
	highram (rw) : ORIGIN = 0xe000, LENGTH = 0x2000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0x100;
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
	} >highram AT>ram

	.dummy : {
		BIOS_SECTOR_COUNT = ((. - LOADADDR(.loader)) + 255) / 256;
	} AT>ram
}

OUTPUT_FORMAT {
	TRIM(ram)
}


