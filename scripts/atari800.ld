/*
 * Atari 400/800/600XL Linker Script
 *
 * RAM minimum: 16kB
 * RAM maximum: 48kB
 *
 * Memory map:
 *
 * 0000-04ff    ZP, stack, Atari OS variables
 * 0500-bfff    RAM
 * c000-cfff    ROM
 * d000-d7ff    Hardware registers
 * d800-ffff    ROM
 *
 * Boot process loads everything at $3000 in 'midram', copies BIOS to 'ram'
 * and sets up the K: IOCB for keyboard input.
 */

MEMORY {
    zp : ORIGIN = 0x80, LENGTH = 0x80
    ram (rw) : ORIGIN = 0x500, LENGTH = 0x800
    midram(rw) : ORIGIN = 0x3000, LENGTH = 0xc00
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0xff;

        . = 0xf0;
        *(.loaderzp)
	} >zp

    .loader : {
        *(loader)
        *loader.o(.text .text.*)
    } >midram

	.text : {
        bios_exec_addr = .;
        bios_load_addr = LOADADDR(.text);
		*(.text .text.*)
	} >ram AT>midram

	.data : {
        *(.data .data.* .rodata .rodata.*)
        bios_end_addr = .;
    } >ram AT>midram

	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
		. = ALIGN(256);
		__SCREENDATA_START__ = .;
		__USERTPA_START__ = .+0x400;
	} >ram
}

OUTPUT_FORMAT {
	TRIM(midram)
}

