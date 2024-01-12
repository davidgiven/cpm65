\ xsend - send files with Xmodem

\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"
.include "drivers.inc"


.bss buffer, 128
.bss blkcnt, 1
.bss checksum, 1

.zp drvserial, 2


SOH = 1         \     H001          Start Of Header
EOT = 4         \     H004          End Of Transmission
ACK = 6         \     H006          Acknowledge (positive)
DLE = 16        \     H010          Data Link Escape
XON =  17       \     H011          Transmit On
XOFF = 19       \     H013          Transmit Off
NAK =   21      \     H015          Negative Acknowledge
SYN =   22      \     H016          Synchronous idle
CAN =   24      \     H018          Cancel5


start:
.expand 1


    ldy #BDOS_GET_BIOS
    jsr BDOS
    sta BIOS+1
    stx BIOS+2

    lda #<welcome_msg
    ldx #>welcome_msg
    jsr print_string


    lda #<DRVID_SERIAL
	ldx #>DRVID_SERIAL
    ldy #BIOS_FINDDRV
    jsr BIOS
    sta drvserial+0
    stx drvserial+1

    bcc found_serial
    lda #<serial_not_found
    ldx #>serial_not_found
    jmp print_string    \ exits

found_serial:
    lda #<serial_found
    ldx #>serial_found
    jsr print_string

    lda drvserial+1
    jsr print_hex_number
    lda drvserial+0
    jsr print_hex_number

    lda #'\r'
    jsr putchar
    lda #'\n'
    jsr putchar

    lda cpm_fcb+1
    cmp #' '
    .label filename_not_given
    .zif eq
        \ No parameter given.
        lda #<filename_not_given
        ldx #>filename_not_given
        jmp print_string    \ exits

    .zendif
    jsr open_file_from_fcb
    .label cant_open_file
    .zif cs
        lda #<cant_open_file
        ldx #>cant_open_file
        jmp print_string    \ exits
    .zendif

    lda #<start_transmission
    ldx #>start_transmission
    jsr print_string

    jsr serial_open


mainloop:


    jsr send_file
    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_CLOSE_FILE
    jsr BDOS


    lda #<done_transmission
    ldx #>done_transmission
    jmp print_string     \ exit


send_file:
    \ load first block into buffer
    jsr fill_buffer    
    lda #1
    sta blkcnt
send_loop:
    \ check for keypress to abort
    ldx #0xff
    ldy #BDOS_CONIO
    jsr BDOS
    cmp #0
    beq check_serial
    lda #CAN
    jsr putserial
    jmp abort_transmission
    
check_serial:
    jsr getserial

    cmp #NAK
    bne check_ack
    \ Got NAK, resend block
    jsr send_block 
    lda #'*'
    jsr putchar
    jmp send_loop
 
check_ack:
    cmp #ACK
    bne send_loop
    \ Got ACK, send next block
    jsr fill_buffer
    bcc ack_send
    lda #EOT
    jsr putserial
    jmp end_of_transmission

ack_send:
    inc blkcnt
    jsr send_block
    lda #'.'
    jsr putchar 
    jmp send_loop    

send_block:
    \ Send header
    lda #SOH
    jsr putserial
    
    lda blkcnt
    jsr putserial
    
    eor #0xff
    jsr putserial

    \ Send data
    lda #0
    sta checksum 
    ldx #0
send_block_loop:
    txa
    pha 
    lda buffer,x
    jsr putserial
    clc
    adc checksum
    sta checksum
    pla
    tax
    inx
    cpx #128
    bne send_block_loop

    \ Send checksum
    lda checksum
    jsr putserial 
 
    rts 

end_of_transmission:
    jsr serial_close
    lda #<transmission_done
    ldx #>transmission_done
    jsr print_string
    clc
    rts

abort_transmission:
    jsr serial_close
    lda #<transmission_stopped
    ldx #>transmission_stopped
    jsr print_string
    sec
    rts

fill_buffer:
    ldy #BDOS_SET_DMA
    lda #<buffer
    ldx #>buffer
    jsr BDOS

    ldy #BDOS_READ_SEQUENTIAL
    lda #<cpm_fcb
    ldx #>cpm_fcb
    jsr BDOS
    rts

open_file_from_fcb:

    lda #<sending_file
    ldx #>sending_file
    jsr print_string

    jsr print_fcb

    lda #0
    sta cpm_fcb+0x20

    lda #<cpm_fcb
    ldx #>cpm_fcb
    ldy #BDOS_OPEN_FILE
    jsr BDOS
    rts

serial_open:
    ldy #SERIAL_OPEN
    jmp (drvserial)

serial_close:
    ldy #SERIAL_CLOSE
    jmp (drvserial)

getserial:
    ldy #SERIAL_INP
    jmp (drvserial)

putserial:
    ldy #SERIAL_OUT
    jmp (drvserial)

\ Prints the name of the file in cpm_fcb.

print_fcb:
    \ Drive letter.

    lda cpm_fcb+0
    .zif ne
        clc
        adc #'@'
        jsr putchar

        lda #':'
        jsr putchar
    .zendif

    \ Main filename.

    ldy #FCB_F1
    .zrepeat
        tya
        pha

        lda cpm_fcb, y
        and #0x7f
        cmp #' '
        .zif ne
            jsr putchar
        .zendif

        pla
        tay
        iny
        cpy #FCB_T1
    .zuntil eq

    lda cpm_fcb+9
    and #0x7f
    cmp #' '
    .zif ne
        lda #'.'
        jsr putchar

        ldy #FCB_T1
        .zrepeat
            tya
            pha

            lda cpm_fcb, y
            and #0x7f
            cmp #' '
            .zif ne
                jsr putchar
            .zendif

            pla
            tay
            iny
            cpy #FCB_T3+1
        .zuntil eq
    .zendif

    lda #'\r'
    jsr putchar
    lda #'\n'
    jsr putchar
    rts


\ Print string wrapper

.zproc print_string
    ldy #BDOS_PRINTSTRING
    jmp BDOS
.zendproc

\ Prints XA in decimal. Y is the padding char or 0 for no padding.

\ Prints an 8-bit hex number in A.
.zproc print_hex_number
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr h4
    pla
h4:
    and #0x0f
    ora #'0'
    cmp #'9'+1
	.zif cs
		adc #6
	.zendif
    pha
    jsr putchar
	pla
	rts
.zendproc

.zproc putchar

	ldy #BDOS_CONOUT
    jmp BDOS

.zendproc



BIOS:
    jmp 0

serial_not_found:
    .byte "error : cannot find serial device\r\n$"

filename_not_given:
    .byte "error : please add filename to send as parameter\r\n$"

transmission_stopped:
    .byte "error : transmission stopped\r\n$"


cant_open_file:
    .byte "cannot open file\r\n$"


serial_found:
    .byte "info : found serial device at :$"

sending_file:
    .byte "info : sending file : $"

start_transmission:
    .byte "info : Waiting for receiver\r\n"
    .byte "Press any key to cancel\r\n$"    

done_transmission:
    .byte "info : Everything finished. Bye \r\n$"


transmission_done:
    .byte "\r\ninfo : transmission complete\r\n$"

welcome_msg:
    .byte "\r\nxmodem-send\r\nSends x-modem protocol data from disk to serial-device\r\n$"



