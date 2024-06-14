; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"
#include "jumptables.inc" 	
IO_page_uart = $01
IO_page_sdcard = $03
IO_page_video = $04
IO_page_reg = $00
ROM_sel_reg = $02

tty_write = $fe06
tty_cls = $fe09
tty_busy = $fe07

sd_base   = $fe00
sd_addr_0 = $fe00
sd_addr_1 = $fe01
sd_addr_2 = $fe02
sd_addr_3 = $fe03
sd_busy   = $fe04
sd_read_strobe = $fe05
sd_write_strobe = $fe06
sd_page = $fe07
sd_done = $fe0a

uart_tx_data = $fe00
uart_tx_done = $fe01
uart_rx_data = $fe02
uart_rx_avail = $fe03


; Offset to second byte of SDCARD adress
; Wasteful, but it's not like we are going to use the full card anyway
BDOS_OFFSET = $1
BDOS_BLOCKS = $0a ; Number of 512 byte blocks to load
CPMFS_OFFSET = $2

ZEROPAGE

.global ptr
.global ptr1
ptr: .word 0
ptr1: .word 0
dma: .fill 2
current_bank: .byte 0
current_drive: .byte 0
sd_offset: .byte 0
sd_page_zp: .byte 0
sd_sector: .fill 4
temp:   .byte 0
; --- Initialisation code ---------------------------------------------------

; Called once on startup and then never again.

zproc _start
    ; Disable ROM
    lda #01
    sta ROM_sel_reg

    lda #'a'
    jsr uart_out
    ; Clear screen

    lda #IO_page_video
    sta IO_page_reg
    sta tty_cls
   
    lda #'b'
    jsr uart_out 
    ; Print banner
 
    ldy #banner_end - banner
    zrepeat
banner_wait:
        lda tty_busy
        bne banner_wait 
        lda banner - 1, y        
        sta tty_write 
        dey
    zuntil_eq

    lda #'c'
    jsr uart_out
    ; Load the BDOS image.
    lda #BDOS_OFFSET
    sta sd_offset
    lda mem_base
    clc
    adc #$30
    jsr uart_out
    lda mem_base
    jsr load_bdos
   
    lda #'d'
    jsr uart_out 
    ; Relocate it.

    lda mem_base
    ldx zp_base
    jsr bios_RELOCATE


    lda #'e'
    jsr uart_out
    ; Open CPMFS
    	
    lda #CPMFS_OFFSET
    sta sd_offset
    
    ; Initialize drivers
    jsr initdrivers

    lda #'f'
    jsr uart_out
    ; Avoid junk character in buffer at startup
    lda #$00
    sta pending_key

    ; Compute the entry address and jump.

    lda mem_base
    pha
    lda #COMHDR_ENTRY-1 ; rts addresses are one before the target
    pha

    lda #<biosentry
    ldx #>biosentry
    
    ;jmp mem_base + COMHDR_ENTRY

    rts                 ; indirect jump
zendproc
    
banner: ; reversed!
    .byte 13, 10
    .ascii "-------------------- 2056onan rof 56-M/PC --------------------"
banner_end:
    ; Filler
    .byte 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00, 00
; Stuff above of here must be 0x80 long, currently OK

; ---- Drive filenames -----
#cpmfs_filename:
#    .ascii "CPMFS"
#    .byte 00

; --- Drivers -------------------------------------------------------
.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

; TTY driver strategy routine
; Y = TTY opcode

zproc drvstrat_TTY
    jmpdispatch jmptable_lo, jmptable_hi

jmptable_lo:
    jmptablo tty_const
    jmptablo tty_conin
    jmptablo tty_conout
jmptable_hi:
    jmptabhi tty_const
    jmptabhi tty_conin
    jmptabhi tty_conout
zendproc


;defdriver SCREEN, DRVID_SCREEN, drvstrat_SCREEN, 0

; SCREEN driver strategy routine
; Y = TTY opcode

;zproc drvstrat_SCREEN
;    jmpdispatch screen_jmptable_lo, screen_jmptable_hi

;screen_jmptable_lo:
;    jmptablo screen_version
;    jmptablo screen_getsize
;    jmptablo screen_clear
;    jmptablo screen_setcursor
;    jmptablo screen_getcursor
;    jmptablo screen_putchar
;    jmptablo screen_putstring
;    jmptablo screen_getchar
;    jmptablo screen_showcursor
;    jmptablo screen_scrollup
;    jmptablo screen_scrolldown
;    jmptablo screen_cleartoeol
;    jmptablo screen_setstyle
;screen_jmptable_hi:
;    jmptabhi screen_version
;    jmptabhi screen_getsize
;    jmptabhi screen_clear
;    jmptabhi screen_setcursor
;    jmptabhi screen_getcursor
;    jmptabhi screen_putchar
;    jmptabhi screen_putstring
;    jmptabhi screen_getchar
;    jmptabhi screen_showcursor
;    jmptabhi screen_scrollup
;    jmptabhi screen_scrolldown
;    jmptabhi screen_cleartoeol
;    jmptabhi screen_setstyle
;zendproc

; SERIAL driver strategy routine
; Y = TTY opcode

;defdriver "SERIAL", DRVID_SERIAL, drvstrat_SERIAL, 0

;zproc drvstrat_SERIAL
;    jmpdispatch serial_jmptable_lo, serial_jmptable_hi

;serial_jmptable_lo:
;    jmptablo serial_inp
;    jmptablo serial_out
;    jmptablo serial_open
;    jmptablo serial_close
;    jmptablo serial_outp
;    jmptablo serial_in    
;serial_jmptable_hi:
;    jmptabhi serial_inp
;    jmptabhi serial_out
;    jmptabhi serial_open
;    jmptabhi serial_close
;    jmptabhi serial_outp
;    jmptabhi serial_in 
;zendproc 

; --- SERIAL driver -------------------------------------------------------

;zproc serial_inp
;    jsr ACIA3_Scan
;    rts     
;zendproc

;zproc serial_out
;    jmp ACIA3_Output     
;zendproc

;zproc serial_open
;    jmp ACIA3_init
;zendproc

;zproc serial_close
;    rts
;zendproc

;zproc serial_outp
;    jsr ACIA3_Output
;    clc
;    rts
;zendproc

;zproc serial_in
;    jmp ACIA3_Input
;zendproc

; --- SCREEN driver -------------------------------------------------------

;zproc screen_version
;    lda #0
;    rts
;zendproc

;zproc screen_getsize
;    ; Screen size is 80x30
;    lda #79
;    ldx #29
;    rts
;zendproc

;zproc screen_clear
;    jmp jmp_cls
;zendproc

;zproc screen_setcursor
;    jmp jmp_setcursor
;zendproc

;zproc screen_getcursor
;    lda vidcursor_x
;    ldx vidcursor_y
;    rts
;zendproc

;zproc screen_putchar
;    ora vid_style
;    ldy #0
;    sta (vidpointer),Y

;   lda #63
;    cmp vidcursor_x
;    beq screen_putchar_done
;    inc vidcursor_x
;    lda vidcursor_x
;    ldx vidcursor_y
;    jsr screen_setcursor 
;screen_putchar_done:
;    rts    
;zendproc

;zproc screen_putstring
;    sta ptr+0
;    stx ptr+1
;    ldy #0
;putstring_loop:
;    lda (ptr),y
;    beq putstring_endloop
;    jsr jmp_out 
;    iny
;    jmp putstring_loop
;putstring_endloop:
;    clc
;    rts
;zendproc

;zproc screen_getchar
;    jsr jmp_scan
;    cmp #00
;    beq nodata
;    cmp #$08
;    bne notbs
;    lda #127
;notbs:    
;    clc
;    rts
;nodata:
;    sec   
;    rts
;zendproc

;zproc screen_showcursor
;    jmp jmp_showcursor
;zendproc

;zproc screen_scrollup
;    jmp jmp_scrollup
;zendproc

;zproc screen_scrolldown
;    jmp jmp_scrolldown
;zendproc

;zproc screen_cleartoeol
;    jmp jmp_cleartoeol
;zendproc

;zproc screen_setstyle
;    cmp #$01
;    bne normal_style
;    lda #$80
;    sta vid_style
;    rts
;normal_style:
;    lda #$00
;    sta vid_style
;    rts
;zendproc

; --- TTY driver -------------------------------------------------------

; Returns 0x00 if no key is pending, 0xff if one is.
; C if no key is pending, !C if key pending
zproc tty_const
    lda pending_key
    zif_eq
        lda #IO_page_uart
        sta IO_page_reg
        lda uart_rx_avail
        zif_eq
            lda #$00
            sec
            rts
        zendif
        lda uart_rx_data
        sta pending_key
    zendif
    lda #$ff
    clc
    rts
zendproc

; Blocks and waits for the next keypress; returns it in A.

zproc tty_conin
    lda pending_key
    zif_eq
	    lda #IO_page_uart
        sta IO_page_reg
tty_input_wait:
        lda uart_rx_avail
        beq tty_input_wait
        lda uart_rx_data    
        rts
    zendif

    ldx #0
    stx pending_key
    rts
zendproc

zproc tty_conout
	cmp #127
	zif_eq
		lda #8
	zendif
    pha
    lda #IO_page_video
    sta IO_page_reg
    pla
    sta tty_write 
    rts
zendproc

; -- Rest of the BIOS ---

; Sets the current DMA address.

zproc bios_SETDMA
    sta dma+0
    stx dma+1
    rts
zendproc

; Select a disk.
; A is the disk number.
; Returns the DPH in XA.
; Sets carry on error.

zproc bios_SELDSK
    cmp #0
    zif_ne
        sec                 ; invalid drive
        rts
    zendif

    lda #<dph
    ldx #>dph
    clc
    rts
zendproc

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    ; CP/M sector length is 128 bytes
    ; SD card sector length is 512 bytes
    ; Setup adressing...    
    sta ptr
    stx ptr+1

    ; Set SD card IO page
    lda #IO_page_sdcard
    sta IO_page_reg

    ; Get page offset
    ldy #0
    lda (ptr),y
    and #$03
    sta sd_page_zp
    sta sd_page

    ; Divide sector address by 4 to get correct SD sector
    ldx #2
divloop:
    ldy #2
    lda (ptr),y
    lsr
    sta (ptr),y
    
    dey
    lda (ptr),y
    ror
    sta (ptr),y

    dey
    lda (ptr),y
    ror     
    sta (ptr),y   
    dex
    bne divloop

    lda #0
    sta sd_offset+3

    ldy #2
    lda (ptr),y
    sta sd_offset+2

    ldy #1
    lda (ptr),y
    sta sd_offset+1
    
    ldy #0
    sta (ptr),y
    sta sd_offset+0

    clc
    lda sd_offset+1
    adc CPMFS_OFFSET
    sta sd_offset+1
    bcc offset_done
    inc sd_offset+2
 offset_done:
    jsr sync_sd_offset

    rts
zendproc
    
zproc bios_READ
	;jsr jmp_locate
    ;lda dma;#<dma
    ;ldx dma+1;#>dma
    ;jsr jmp_read_sector
    
    ; Setup pointer
    lda dma
    sta ptr
    lda dma+1
    sta ptr+1

    ; Perform SD-card read
    jsr sdcard_read 

    ; Copy data to dma
    ldx #$80
    ldy #0
readcopyloop:
    lda sd_base, X
    sta (ptr),Y
    iny
    bne readcopycont
    inc ptr+1
readcopycont:
    inx
    bne readcopyloop

    rts
zendproc

zproc bios_WRITE
	;jsr jmp_locate
    ;lda dma;#<dma
    ;ldx dma+1;#>dma
    ;jsr jmp_write_sector
     ; Setup pointer
    lda dma
    sta ptr
    lda dma+1
    sta ptr+1

    ; Perform SD-card read
    jsr sdcard_read 

    ; Copy data from dma
    ldx #$80
    ldy #0
writecopyloop:
    lda (ptr),Y
    sta sd_base, X
    iny
    bne writecopycont
    inc ptr+1
writecopycont:
    inx
    bne writecopyloop

    ; Write to SD-card
    lda #01
    sta sd_write_strobe

    rts
zendproc

zproc bios_GETTPA
    ;ldy current_bank
    lda mem_base;, Y  
    ldx mem_end;, Y
    rts
zendproc

zproc bios_SETTPA
    ldy current_bank
    cpy #0
    bne settpa_end
    sta mem_base;, Y 
    stx mem_end;, Y
settpa_end:
    rts
zendproc

zproc bios_GETZP
    ;ldy current_bank
    lda zp_base;, Y
    ldx zp_end;, Y
    rts
zendproc

zproc bios_SETZP
    sta zp_base;, Y 
    stx zp_end;, Y
    rts
zendproc

zproc bios_SETBANK
    sta current_bank
    rts
zendproc

zproc sdcard_read
    lda #IO_page_sdcard
    sta IO_page_reg
    
    jsr sync_sd_offset

    ; Read strobe
    lda #1
    sta sd_read_strobe
sd_read_busy:
    lda sd_busy
    bne sd_read_busy    

    rts
zendproc

zproc load_bdos
    ; Push load adress unto stack
    pha

    ; Set IO page
    lda #IO_page_sdcard
    sta IO_page_reg

    ; Set offset to BDOS address
    lda #BDOS_OFFSET
    sta sd_sector+1
    lda #0
    sta sd_sector
    sta sd_sector+2
    sta sd_sector+3
    sta sd_page_zp
    
    jsr sync_sd_offset

    ; Read the BDOS blocks
    lda #BDOS_BLOCKS+1
    sta ptr1
    ldy #0
    lda #0
    sta ptr
    pla
    sta ptr+1 
bdos_sector_read:
    ; read strobe
    lda #1
    sta sd_read_strobe
bdos_read_wait:
    lda sd_busy
    bne bdos_read_wait

    ; Copy data to RAM
bdos_bank_loop:
    ldx #$80
bdos_copy_loop:
    lda sd_base,X
    sta (ptr),Y 
    iny     
    bne bdos_copy_cont
    inc ptr+1
bdos_copy_cont:
    inx
    bne bdos_copy_loop

    inc sd_page_zp
    jsr sync_sd_offset
    lda sd_page_zp
    cmp #04
    bne bdos_bank_loop
    
bdos_copy_done:
    dec ptr1
    lda ptr1
    clc
    adc #$30
    jsr uart_out
    lda ptr1
    beq bdos_all_done

    ; Increase SD sector address
    inc sd_sector
    bne bdos_inc_done
    inc sd_sector+1
    bne bdos_inc_done
    inc sd_sector+2
    bne bdos_inc_done
    inc sd_sector+3
bdos_inc_done:
    lda #0
    sta sd_page_zp
    jsr sync_sd_offset
    jmp bdos_sector_read
bdos_all_done:
    rts
zendproc

zproc sync_sd_offset
    lda #'S'    
    jsr uart_out
    lda sd_sector+1
    clc
    adc #$30
    jsr uart_out
    lda #13
    jsr uart_out
    lda #10
    jsr uart_out
    
    ; Set IO page
    lda #IO_page_sdcard
    sta IO_page_reg    

    ; Wait until SD-card is not busy
sd_offset_wait:
    lda sd_busy
    bne sd_offset_wait    

    lda sd_sector
    sta sd_addr_0
    lda sd_sector+1
    sta sd_addr_1
    lda sd_sector+2
    sta sd_addr_2
    lda sd_sector+3
    sta sd_addr_3    
    lda sd_page_zp
    sta sd_page
    rts
zendproc

zproc uart_out
    pha
    ; Preserve io page
    lda IO_page_reg
    sta temp
    
    lda #IO_page_uart
    sta IO_page_reg

uart_out_wait:
    lda uart_tx_done
    beq uart_out_wait

    pla
    sta uart_tx_data

    lda temp
    sta IO_page_reg
    rts
zendproc

.data
;current_bank:   .byte 0
zp_base: .byte __ZP0_START__;, __ZP1_START__
zp_end:  .byte __ZP0_END__;, __ZP1_END__

mem_base: .byte __TPA0_START__@mos16hi
mem_end:  .byte __TPA0_END__@mos16hi
	
; DPH for drives

define_drive dph, 128*64, 2048, 128, 0

directory_buffer = _start
NOINIT

pending_key: .byte 0    ; pending keypress from system
sector_num:  .fill 3    ; current absolute sector number
	
; vim: filetype=asm sw=4 ts=4 et

