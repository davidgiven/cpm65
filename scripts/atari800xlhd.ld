/*
 * Atari 800XL/65XE/130XE Linker Script
 *
 * RAM: 62kB
 *
 * Memory map:
 *
 * 0000-04ff    ZP, stack, Atari OS variables
 * 0500-cfff    RAM
 * d000-d7ff    Hardware registers
 * d800-ffff    RAM (d800-dfff, e000-e3ff copy of font, e400-ffff)
 *
 * Boot process loads everything at $3000 in 'midram', copies BIOS to
 * 'biosram' at $d800, copies SIO/CIO wrappers and interrupt handlers
 * to 'lowram', sets up the K: IOCB for keyboard input, installs handlers,
 * copies system font to RAM, and loads BDOS to 'bank_extra'.
 */

MEMORY {
    zp : ORIGIN = 0x80, LENGTH = 0x80
    lowram (rw) : ORIGIN = 0x500, LENGTH = 0x800
    midram(rw) : ORIGIN = 0x3000, LENGTH = 0x800
    biosram(rw) : ORIGIN = 0xd800, LENGTH = 0x800
    bank_extra(rw) : ORIGIN = 0xe400, LENGTH = 0x1c00
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
	} >biosram AT>midram

	.data : {
        *(.data .data.* .rodata .rodata.*)
        bios_end_addr = .;
    } >biosram AT>midram

    .wrappers : {
        wrappers_exec_addr = .;
        wrappers_load_addr = LOADADDR(.wrappers);
        *(wrappers)
        *wrappers.o(.text .text.*)
        wrappers_end_addr = .;
    } >lowram AT>midram

    .wrappersnoinit (NOLOAD): {
        *(wrappersnoinit)
		. = ALIGN(256);
		__SCREENDATA_START__ = .;
		__USERTPA_START__ = .+0x400;
    } >lowram

	.noinit (NOLOAD) : {
		*(.noinit .noinit.*)
	} >biosram
}

OUTPUT_FORMAT {
	TRIM(midram)
}

