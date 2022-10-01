.macro CPM65_BARE_HEADER
	.import __ZEROPAGE_SIZE__
	.import __CODE_RUN__
	.import __BSS_RUN__
    .import __BSS_SIZE__

	.byte <__ZEROPAGE_SIZE__
    .byte >(__BSS_RUN__ + __BSS_SIZE__ - __CODE_RUN__ + 255)
	.word PBLOCK_START ; relocation data here in the file

    .segment "PBLOCK"
PBLOCK_START:
    .code
.endmacro

.macro CPM65_COM_HEADER
	CPM65_BARE_HEADER
.export BDOS
BDOS:
	jmp 0
ENTRY:

    .segment "PBLOCK"
FCB:         .res 37
COMMANDLINE: .res 128
    .code

.endmacro

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

.enum cpme
    ok        = $00 ; success (usually)
    nodata    = $01 ; or EOF
    diskfull  = $02 ; no free blocks on disk
    cantclose = $03 ; can't write extent back to disk
    noextent  = $04 ; only on random access reads
    dirfull   = $05 ; no free dirents on disk
    badfcb    = $09 ; FCB couldn't be parsed
    failed    = $ff ; general purpose failure code
.endenum

.struct dph
    xlt      .word
    cdrmax   .word
    scratch1 .word
    scratch2 .word
    dirbuf   .word
    dpb      .word
    csv      .word
    alv      .word
.endstruct

.struct comhdr
    zp_usage    .byte ; bytes of zero page used
    tpa_usage   .byte ; pages of TPA required (including space for relocation)
    rel_offset  .word ; relative address of relocation data and start of BSS
                .byte ; BDOS entrypoint jump
    bdos        .word
    entry       .byte
.endstruct

.macro define_drive sectors, blocksize, dirents, reserved
    .scope
        .word 0, 0, 0, 0    ; CP/M workspace
        .word directory_buffer
        .word dpb
        .word checksum_buffer
        .word allocation_vector

        .if blocksize = 1024
            block_shift = 3
        .elseif blocksize = 2048
            block_shift = 4
        .elseif blocksize = 4096
            block_shift = 5
        .elseif blocksize = 8192
            block_shift = 6
        .elseif blocksize = 16384
            block_shift = 7
        .else
            .fatal "Invalid block size!"
        .endif

        checksum_buffer_size = (dirents+3) / 4
        blocks_on_disk = sectors * 128 / blocksize
        allocation_vector_size = (blocks_on_disk + 7) / 8
        directory_blocks = (dirents * 32) / blocksize

        .if directory_blocks = 0
            .fatal "Directory must be at least one block in size!"
        .endif
        .if ((dirents * 32) .mod blocksize) <> 0
            .fatal "Directory is not an even number of blocks in size!"
        .endif

        .if blocks_on_disk < 256
            .if blocksize = 1024
                extent_mask = %00000000
            .elseif blocksize = 2048
                extent_mask = %00000001
            .elseif blocksize = 4096
                extent_mask = %00000011
            .elseif blocksize = 8192
                extent_mask = %00000111
            .elseif blocksize = 16384
                extent_mask = %00001111
            .endif
        .else
            .if blocksize = 1024
                .fatal "Can't use a block size of 1024 on a large disk"
            .elseif blocksize = 2048
                extent_mask = %00000000
            .elseif blocksize = 4096
                extent_mask = %00000001
            .elseif blocksize = 8192
                extent_mask = %00000011
            .elseif blocksize = 16384
                extent_mask = %00000111
            .endif
        .endif
    dpb:
        .word 0             ; unused
        .byte block_shift   ; block shift
        .byte (1<<block_shift)-1 ; block mask
        .byte extent_mask   ; extent mask
        .word blocks_on_disk - 1 ; number of blocks on the disk
        .word dirents - 1   ; number of directory entries
        .dbyt ($ffff << (16 - directory_blocks)) & $ffff ; allocation bitmap
        .word checksum_buffer_size ; checksum vector size
        .word reserved      ; number of reserved _sectors_ on disk

        .pushseg
        .bss
        checksum_buffer: .res checksum_buffer_size
        allocation_vector: .res allocation_vector_size

        .popseg
    .endscope
.endmacro

; vim: filetype=asm sw=4 ts=4 et

