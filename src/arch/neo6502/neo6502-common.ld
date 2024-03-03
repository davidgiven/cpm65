 /* Common part of the Neo6502 loader script. This generates the BIOS proper,
  * at the top of RAM. */

BIOS_TOP = 0xff00;

.zp : {
    *(.zp .zp.*)
    __ZEROPAGE_START__ = .;
    __ZEROPAGE_END__ = 0xff;
} >zp

.loader : {
    __header_start = .;
    LONG(0x4f454e03);                   // magic number
    SHORT(0);                           // firmware version
    SHORT(_start);                      // execute address
    BYTE(0);                            // control byte
    SHORT(_start);                     // load address
    SHORT(SIZEOF(.loader) + SIZEOF(.data) + SIZEOF(.text) - (__header_end - __header_start)); // length
    BYTE(0);                            // ASCIIZ comment (empty)
    __header_end = .;
    
    *(loader)
    *loader.o(.text .text.*)
	BIOS_LOAD_ADDR = .;
} >initram

.bss (BIOS_TOP - BIOS_SIZE) (NOLOAD) : {
    *(.bss .bss.*)
    *(.noinit .noinit.*)
    bios_data_start = .;
} >hiram

.data : {
	BIOS_EXEC_ADDR = .;
    *(.data .data.* .rodata .rodata.*)
} >hiram AT>initram

.text : {
    *(.text .text.*) 
    *(tail)
} >hiram AT>initram

__TPA0_START__ = 0x0200;
__TPA0_END__ = ADDR(.bss);
