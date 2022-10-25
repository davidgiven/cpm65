
MEMORY {
    zp : ORIGIN = 0x80, LENGTH = 0x80
    ram (rw) : ORIGIN = 0x600, LENGTH = 0x400
}

SECTIONS {
	.zp : {
		*(.zp .zp.*)
		__USERZEROPAGE_START__ = .;
		__USERZEROPAGE_END__ = 0x100;
	} >zp

	.text : { *(.text .text.*) } >ram
	.data : {
          *(.data .data.* .rodata .rodata.*)
          __data_end = .;
    } > ram
	.noinit (NOLOAD) : { *(.noinit .noinit.*) } >ram
}

OUTPUT_FORMAT {
    /* XEX magic number. */
    SHORT(0xffff)
    /* First byte of Run vector. */
    SHORT(0x02e0)
    /* Last byte of Run vector. */
    SHORT(0x02e1)
    /* Segment to be loaded to Run vector. */
    SHORT(_start)
    /* Address where first byte of main segment should be loaded. */
    SHORT(0x2000)
    /* Address of last byte of main segment.
       -- is a hack to force the early evalutation of __data_end; otherwise the
       -1 offset may be interpreted as requesting the end of the containing
       section. */
    SHORT(--__data_end - 1)

    TRIM(ram)
}
