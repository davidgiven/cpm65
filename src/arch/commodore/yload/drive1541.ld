MEMORY {
    code1 (rw) : ORIGIN = 0x0146, LENGTH = 0x0074 # 146..1ba
    code2 (rw) : ORIGIN = 0x0200, LENGTH = 0x002b # 200..22b
    code5 (rw) : ORIGIN = 0x027a, LENGTH = 0x0010 # 27a..28a
    code6 (rw) : ORIGIN = 0x0300, LENGTH = 0x0100 # 300..400 (must be last)
}

SECTIONS {
	.code1 : { *(.code1) } >code1
	.code2 : { *(.code2) } >code2
	.code5 : { *(.code5) } >code5
	.code6 : { *(.code6) } >code6
}
