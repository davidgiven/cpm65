
main sect rel
bank0 group main

start:
    mem8
    idx8
    sei
    rep #0b00001001     ; binary mode
    xce                 ; native mode

    rts

cop_e_entry:
brk_e_entry:
abt_e_entry:
int_e_entry:
    rti

    org 0xffc0

    ;      012345678901234567890
    ascii 'CP/M-65 SNES         '
    byte 0b00110001     ; fast, HiROM
    byte 0x02           ; ROM + RAM + battery
    byte 9              ; ROM size: 512kB
    byte 5              ; RAM size: 32kB
    byte 0              ; country
    byte 0              ; developer ID
    byte 0              ; version
    word 0              ; checksum complement (filled in later)
    word 0              ; checksum (filled in later)

    ; Native mode vectors

    word 0xffff         ; reserved
    word 0xffff         ; reserved
    word 0xffff         ; COP
    word 0xffff         ; BRK
    word 0xffff         ; ABT
    word 0xffff         ; NMI
    word 0xffff         ; reserved
    word 0xffff         ; IRQ

    ; Emulation mode vectors

    word 0xffff         ; reserved
    word 0xffff         ; reserved
    word cop_e_entry
    word brk_e_entry
    word abt_e_entry
    word int_e_entry    ; NMI
    word start          ; reserved
    word int_e_entry    ; IRQ

    end
