\ cpudetect - info about cpu

\ Copyright © 2023 by David Given and Sven Oliver Moll

\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

.include "cpm65.inc"

start:
   lda   #$01
   .byte $eb,$ea \ 6502: sbc #$ea, 65C02: nop:nop, 65816: xba:nop
   sec
   lda   #$ea
   .byte $eb,$ea \ 6502: sbc #$ea, 65C02: nop:nop, 65816: xba:nop
\ A: 6502: A=$00, 65C02: A=$ea, 65816: A=$01
   cmp   #$02
   .zif cs
      lda   #$02
   .zendif
   pha
   lda   #<txtbase
   ldx   #>txtbase
   ldy   #BDOS_PRINTSTRING
   jsr   BDOS

   ldx   #>txtcpus
   pla
   asl   A
   asl   A
   asl   A
   adc   #<txtcpus
   .zif cs
      inx
   .zendif
   ldy   #BDOS_PRINTSTRING
   jmp   BDOS

txtbase:
   .byte "CPU is $"
txtcpus: \ all texts need to be 8 characters
   .byte "6502 \r\n$"
   .byte "65816\r\n$"
   .byte "65C02\r\n$"

