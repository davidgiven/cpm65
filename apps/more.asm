\ Copyright © 2025 Henrik Löfgren
\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

\ More utility, for viewing long text files

.include "cpm65.inc"
.include "drivers.inc"

.zp linepos, 1
.zp colpos, 1
.zp linemax, 1
.zp colmax, 1
.zp screen_present, 1
.zp temp, 1

.label BIOS
.label SCREEN

.label cannot_open
.label newline
.label syntax_error
.label more_wait
.label more_wait_print
.label more_exit

.expand 1
.label printchar

zproc start
	\ Did we get a parameter?

	lda cpm_fcb + 1
	cmp #' '
	beq syntax_error

    \ Set default values used without screen driver
    lda #0
    sta screen_present
    sta linepos
    sta colpos
    lda #39
    sta colmax
    lda #19
    sta linemax

    \ Check if the screen driver is available
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS

    \ Driver found?
    zif cc
        sta SCREEN+1
        stx SCREEN+2
        lda #1
        sta screen_present
        
        \ Get screen size
        ldy #SCREEN_GETSIZE
        jsr SCREEN
        sta colmax
        stx linemax
        dec linemax
    
        \ Clear screen
        ldy #SCREEN_CLEAR
        jsr SCREEN

        \ Set cursor position at 0,0
        lda #0
        ldx #0
        ldy #SCREEN_SETCURSOR
        jsr SCREEN
    zendif
    
	\ Try and open the file.

	lda #0
	sta cpm_fcb+0x20 \ must clear CR before opening. Why?
	lda #<cpm_fcb
	ldx #>cpm_fcb
	ldy #BDOS_OPEN_FILE
	jsr BDOS
	bcs cannot_open


	\ Print the file

	lda #<cpm_default_dma
	ldx #>cpm_default_dma
	ldy #BDOS_SET_DMA
	jsr BDOS

	zloop
		lda #<cpm_fcb
		ldx #>cpm_fcb
		ldy #BDOS_READ_SEQUENTIAL
		jsr BDOS
		zbreak cs
	    
        ldy #128
        sty temp
        zrepeat
            ldy temp
            lda cpm_default_dma-128,y
            cmp #26
            beq more_exit
            cmp #13
            zif eq
                lda #0
                sta colpos
                inc linepos
                lda #13
            zendif 
            ldy #BDOS_CONOUT
            jsr BDOS

            inc colpos
            lda colpos
            cmp colmax
            zif eq
                lda #0
                sta colpos
                inc linepos
            zendif
            lda linepos
            cmp linemax
            zif eq
                lda #0
                sta linepos
                jsr more_wait
                cmp #'q'
                beq more_exit
                cmp #'Q'
                beq more_exit
                cmp #3
                beq more_exit

                jsr newline
                lda screen_present
                cmp #1
                zif eq
                    ldy #SCREEN_CLEAR
                    jsr SCREEN
                    
                    lda #0
                    ldx #0
                    ldy #SCREEN_SETCURSOR
                    jsr SCREEN
                zendif
            zendif
            inc temp
        zuntil eq
    zendloop
	
more_exit:
    jmp newline
    rts    
zendproc

BIOS:
    jmp 0

SCREEN:
    jmp 0
	
zproc syntax_error
	lda #<msg
	ldx #>msg
	ldy #BDOS_PRINTSTRING
	jmp BDOS
msg:
	.byte "Syntax error", 13, 10, 0
zendproc

zproc cannot_open
	lda #<msg
	ldx #>msg
	ldy #BDOS_PRINTSTRING
	jmp BDOS
msg:
	.byte "Cannot open file", 13, 10, 0
zendproc

zproc more_wait
    jsr newline
    jsr more_wait_print
    \ Wait for a keystroke
    ldx #0xfd
    ldy #BDOS_CONIO
    jsr BDOS
    rts
zendproc

zproc more_wait_print
    lda #<msg
    ldx #>msg
    ldy #BDOS_PRINTSTRING
    jmp BDOS
msg:
    .byte "--More--", 0    
zendproc

zproc printchar
    ldy #BDOS_CONOUT
    jmp BDOS
zendproc

zproc newline
	lda #13
	jsr printchar
	lda #10
	jmp printchar
zendproc

\ vim: filetype=asm sw=4 ts=4 et


