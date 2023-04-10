/* This performs a fake link, so that we can see how big the BIOS is going to
 * be, so it can get placed properly at the end of memory in the real link.
 * Sigh, ld. */

MEMORY {
    zp : ORIGIN = 2, LENGTH = 0xfe
    ram (rw) : ORIGIN = 0x800, LENGTH = 0x1000
	midram (rw) : ORIGIN = 0x8000, LENGTH = 0x1000
	highram (rw) : ORIGIN = 0x9000, LENGTH = 0x4000
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
		*(tail)
	} >highram AT>ram

	.dummy : {
		BIOS_SECTOR_COUNT = ((. - LOADADDR(.loader)) + 255) / 256;
	} AT>ram
}

