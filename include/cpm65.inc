.macro CPM65_BARE_HEADER
	.import __ZEROPAGE_SIZE__
	.import __CODE_RUN__
	.import __BSS_RUN__
    .import __BSS_SIZE__

	.byte <__ZEROPAGE_SIZE__
    .byte >(__BSS_RUN__ + __BSS_SIZE__ - __CODE_RUN__ + 255)
	.byte >(__BSS_RUN__ - __CODE_RUN__ + 255)
.endmacro

.macro CPM65_COM_HEADER
	CPM65_BARE_HEADER
.export BDOS
BDOS:
	jmp 0
ENTRY:

.endmacro

HDR_ZPSIZE = 0
HDR_RELOTABLE_OFFSET = 1

.enum fcb
    dr
    f1
    f2
    f3
    f4
    f5
    f6
    f7
    f8
    t1
    t2
    t3
    ex
    s1
    s2
    rc
    al
    cr = $20
    r0
    r1
    r2
.endenum

.enum bdos
    exit_program = 0
    console_input = 1
    console_output = 2
    aux_input = 3
    aux_output = 4
    printer_output = 5
    direct_io = 6
    get_io_byte = 7
    set_io_byte = 8
    write_string = 9
    read_line = 10
    console_status = 11
    get_version = 12
    reset_disks = 13
    select_disk = 14
    open_file = 15
    close_file = 16
    find_first = 17
    find_next = 18
    delete_file = 19
    read_sequential = 20
    write_sequential = 21
    create_file = 22
    rename_file = 23
    get_login_bitmap = 24
    get_current_drive = 25
    set_dma_address = 26
    get_allocation_bitmap = 27
    set_drive_readonly = 28
    get_readonly_bitmap = 29
    set_file_attributes = 30
    get_DPB = 31
    get_set_user_number = 32
    read_random = 33
    write_random = 34
    compute_file_size = 35
    compute_random_pointer = 36
    reset_disk = 37
    get_bios = 38
    write_random_filled = 40
.endenum

.enum bios
	const
	conin
	conout
	seldsk
	setsec
	setdma
	read
	write
	relocate
	gettpa
	settpa
	getzp
	setzp
.endenum

.struct dph
    xlt    .word
    cdrmax .word
    scratch1 .word
    scratch2 .word
    dirbuf .word
    dpb    .word
    csv    .word
    alv    .word
.endstruct

.struct comhdr
    zp_usage    .byte ; bytes of zero page used
    tpa_usage   .byte ; pages of TPA used
    rel_offset  .byte ; relative page of relocation data
                .byte ; BDOS entrypoint jump
    bdos        .word
    entry       .byte
.endstruct

; vim: filetype=asm sw=4 ts=4 et

