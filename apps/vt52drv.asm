\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"

.expand 1

.label entry
.label next
.label noscreen
.label SCREEN
.label par_done
.label mescdone

ESC = 0x1b
BELL = 0x07
BACKSPACE = 0x08
TAB = 0x09
CR = 0x0d
LF = 0x0a

\ --- Resident part starts at the top of the file ---------------------------

.bss max_x,1
.bss max_y,1
.bss cur_x,1
.bss cur_y,1
.bss mEsc, 1
.bss parse, 1
.bss cnt, 1
.bss inp, 1
.zproc start
    jmp entry
.zendproc

driver:
    .word DRVID_TTY
    .word strategy
    .word 0
    .byte "VT52TTY", 0

.zproc strategy
    cpy #TTY_CONOUT
    .zif eq
        sta inp
        ldy #SCREEN_GETCURSOR
        jsr SCREEN
        sta cur_x
        stx cur_y
        lda #1
        sta parse
        
        lda inp

        cmp #32
        .zif cs
            cmp #127
            .zif cc
                lda mEsc

                cmp #0
                .zif eq
                    \ Regular ASCII
                    lda inp
                    ldy #SCREEN_PUTCHAR
                    jsr SCREEN
                    inc cur_x
                    lda cur_x
                    cmp max_x
                    .zif cs
                        lda #0
                        sta cur_x
                        inc cur_y
                    .zendif
                    lda cur_x
                    ldx cur_y
                    ldy #SCREEN_SETCURSOR
                    jsr SCREEN
                    lda #0
                    sta parse
                    jmp mescdone
                .zendif            
                
                cmp #1
                .zif eq
                    \ escape sequence. Do nothing
                    jmp mescdone
                .zendif
            
                cmp #2
                .zif eq
                    \ First part of cursor adressing
                    lda inp
                    sta mEsc
                    lda #0
                    sta parse
                    jmp mescdone        
                .zendif
                
                \ All other values - second part of cursor adressing
                sec
                lda inp
                sbc #32
                sta cur_x

                sec
                lda mEsc
                sbc #32
                sta cur_y
                
                lda cur_x
                ldx cur_y
                ldy #SCREEN_SETCURSOR
                jsr SCREEN
                
                lda #0
                sta parse
                sta mEsc

                mescdone:
            .zendif
        .zendif
       
        lda inp
        cmp #127
        .zif eq
            lda #BACKSPACE
            sta inp
        .zendif
         
        lda parse
        cmp #1
        .zif eq
            lda inp
            
            cmp #CR
            .zif eq
                lda #0
                sta cur_x
                jmp par_done
            .zendif
            
            cmp #LF
            .zif eq
                inc cur_y
                lda cur_y
                cmp max_y
                .zif cs
                    lda max_y
                    sta cur_y
                    ldy #SCREEN_SCROLLUP
                    jsr SCREEN 
                .zendif
                jmp par_done 
            .zendif
            
            cmp #BACKSPACE
            .zif eq
                dec cur_x
                lda cur_x
                ldx cur_y
                ldy #SCREEN_SETCURSOR
                jsr SCREEN 
                lda #' '
                ldy #SCREEN_PUTCHAR
                jsr SCREEN
                jmp par_done
            .zendif

            cmp #TAB
            .zif eq
                \ Tab to be implemented, need to figure out how to do mod 8
                lda cur_x
                clc
                adc #8
                and #0xf8
                cmp max_x
                .zif cs
                    lda max_x
                .zendif
                sta cur_x
                jmp par_done
            .zendif

            cmp #ESC
            .zif eq
                \ Start of escape sequence
                lda #1
                sta mEsc
                jmp par_done
            .zendif

            cmp #'A'
            .zif eq
                \ Cursor up
                lda #0
                sta mEsc
                
                lda cur_y
                .zif ne
                    dec cur_y
                .zendif
                jmp par_done
            .zendif

            cmp #'B'
            .zif eq
                \ Cursow down
                lda #0
                sta mEsc
                lda cur_y
                cmp max_y
                .zif ne
                    inc cur_y
                .zendif
                jmp par_done
            .zendif
            
            cmp #'C'
            .zif eq
                \ Cursor right
                lda #0
                sta mEsc
                lda cur_x
                cmp max_x
                .zif ne
                    inc cur_x
                .zendif
               jmp par_done 
            .zendif

            cmp #'D'
            .zif eq
                \ Cursor left
                lda #0
                sta mEsc
                lda cur_x
                .zif ne
                    dec cur_x
                .zendif
                jmp par_done
            .zendif

            cmp #'F'
            .zif eq
                \ Enter graphics mode, ignore
                lda #0
                sta mEsc
                jmp par_done
            .zendif
        
            cmp #'G'
            .zif eq
                \ Exit graphics mode, ignore
                lda #0
                sta mEsc
                jmp par_done
            .zendif
            
            cmp #'H'
            .zif eq
                \ Cursor home
                lda #0
                sta mEsc
                sta cur_x
                sta cur_y
                jmp par_done
            .zendif
            
            cmp #'I'
            .zif eq
                \ Reverse line feed
                lda #0
                sta mEsc
                lda cur_y
                .zif ne
                    dec cur_y
                    jmp par_done
                .zendif
                lda #0
                sta cur_y
                ldy #SCREEN_SCROLLDOWN
                jsr SCREEN
                jmp par_done 
            .zendif            
            
            cmp #'J'
            .zif eq
                \ Erase to end of screen
                lda #0
                sta mEsc
                ldy #SCREEN_CLEARTOEOL
                jsr SCREEN
                ldx cur_y
                cpx max_y
                beq par_done
                inx
                .zloop
                    stx cnt
                    lda #0
                    ldy #SCREEN_SETCURSOR
                    jsr SCREEN
                    
                    ldy #SCREEN_CLEARTOEOL
                    jsr SCREEN
                    ldx cnt
                    inx
                    cpx max_y
                    .zbreak cs
                .zendloop
                jmp par_done
            .zendif

            cmp #'K'
            .zif eq
                \ Erase to end of line
                lda #0
                sta mEsc
                ldy #SCREEN_CLEARTOEOL
                jsr SCREEN
                jmp par_done
            .zendif

            cmp #'Y'
            .zif eq
                \ Cursor addressing
                lda #2
                sta mEsc
                jmp par_done
            .zendif

            \ Not a valid escape sequence
            \ Also covers not implemented sequences for screen mode and
            \ alternate keypad mode
            lda #0
            sta mEsc

            par_done:
            lda cur_x
            ldx cur_y
            ldy #SCREEN_SETCURSOR
            jsr SCREEN            

        .zendif
        rts
    .zendif
    \lda inp
    jmp (next)
.zendproc

SCREEN:
    jmp 0

next: .word 0

\ --- Resident part stops here -------------------------------------------

.zproc entry
    
    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    \ Find SCREEN driver and place the jump to it in the resident part
    lda #<DRVID_SCREEN
    ldx #>DRVID_SCREEN
    ldy #BIOS_FINDDRV
    jsr BIOS

    \ Print error message and exit if not found
    .zif cs
        lda #<noscreen
        ldx #>noscreen
        ldy #BDOS_PRINTSTRING
        jsr BDOS
        rts
    .zendif        
    
    sta SCREEN+1
    stx SCREEN+2    

    lda #<banner
    ldx #>banner
    ldy #BDOS_PRINTSTRING
    jsr BDOS

    \ Get screen size and store in resident variables
    ldy #SCREEN_GETSIZE
    jsr SCREEN
    sta max_x
    stx max_y   

    \ Initialize resident variables
    lda #0
    sta mEsc

    \ Find the old TTY driver strategy routine and save it.

    lda #<DRVID_TTY
    ldx #>DRVID_TTY
    ldy #BIOS_FINDDRV
    jsr BIOS
    .zif cc
        sta next+0
        stx next+1

        \ Register the new TTY driver.

        lda #<driver
        ldx #>driver
        ldy #BIOS_ADDDRV
        jsr BIOS
        .zif cc

            \ Our driver uses no ZP, so we don't need to adjust that. But it does use
            \ TPA.

            ldy #BIOS_GETTPA
            jsr BIOS
            clc
            adc #4 \ Allocate 4 pages. We should be using entry to calculate this, but
                   \ the assembler can't do that yet.
            ldy #BIOS_SETTPA
            jsr BIOS

            \ Finished --- don't even need to warm boot.

            rts
        .zendif
    .zendif

    lda #<failed
    ldx #>failed
    ldy #BDOS_PRINTSTRING
    jmp BDOS
    
banner:
    .byte "The TTY driver is now VT52 capable", 13, 10, 0
failed:
    .byte "Failed!", 13, 10, 0
noscreen:
    .byte "SCREEN driver not found!", 13, 10, 0
BIOS:
    jmp 0

\ vim: sw=4 ts=4 et


