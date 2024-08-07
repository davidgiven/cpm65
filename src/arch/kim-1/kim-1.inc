; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

; KIM-1 ROM entry points

OUTCH = 0x1ea0
GETCH = 0x1e5a
DELAY = 0x1ed4
DEHALF = 0x1eeb
EXIT  = 0x1c4f

; KIM-1 I/O

CHAR = $fe             ; ZP char buffer
PORTA = $1700
DDRA = $1701
PORTB = $1702
DDRB = $1703
SAD = $1740            ; 6530 A Data (TTY)
SBD = $1742            ; 6530 B data register