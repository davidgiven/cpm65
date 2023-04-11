/* This performs a fake link, so that we can see how big the BIOS is going to
 * be, so it can get placed properly at the end of memory in the real link.
 * Sigh, ld. */

MEMORY {
    zp : ORIGIN = 0, LENGTH = 0x100
    ram (rw) : ORIGIN = 0x800, LENGTH = 0x1000
	midram (rw) : ORIGIN = 0x8000, LENGTH = 0x1000
	highram (rw) : ORIGIN = 0x9000, LENGTH = 0x4000
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__ZEROPAGE_START__ = .;
		__ZEROPAGE_END__ = 0xff;
	} >zp

	.loader : {
		*(loader)
	} >ram

	.bss (0x10000-BIOS_SIZE) (NOLOAD) : {
		*(.bss .bss.*)
		*(.noinit .noinit.*)
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

	__TPA1_START__ = 0x9000;
	__TPA1_END__   = 0xc000;

	__TPA0_START__ = 0x0800;
	__TPA0_END__   = 0xc000;
}

