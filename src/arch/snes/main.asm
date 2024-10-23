
main sect rel
bank0 group main

start:
    mem8
    idx8
    sei
    rep #00001001b      ; binary mode
    xce                 ; native mode

    rts

cop_e_entry:
brk_e_entry:
abt_e_entry:
int_e_entry:
    rti

    org 0ffc0h

    ;      012345678901234567890
    ascii 'CP/M-65 SNES         '
    byte 00110001b      ; fast, HiROM
    byte 002h           ; ROM + RAM + battery
    byte 9              ; ROM size: 512kB
    byte 5              ; RAM size: 32kB
    byte 0              ; country
    byte 0              ; developer ID
    byte 0              ; version
    word 0              ; checksum complement (filled in later)
    word 0              ; checksum (filled in later)

    ; Native mode vectors

    word 0ffffh         ; reserved
    word 0ffffh         ; reserved
    word 0ffffh         ; COP
    word 0ffffh         ; BRK
    word 0ffffh         ; ABT
    word 0ffffh         ; NMI
    word 0ffffh         ; reserved
    word 0ffffh         ; IRQ

    ; Emulation mode vectors

    word 0ffffh         ; reserved
    word 0ffffh         ; reserved
    word cop_e_entry
    word brk_e_entry
    word abt_e_entry
    word int_e_entry    ; NMI
    word start          ; reserved
    word int_e_entry    ; IRQ

    end
