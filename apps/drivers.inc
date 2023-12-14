\ This file is licensed under the terms of the 2-clause BSD license. Please
\ see the COPYING file in the root project directory for the full text.

DRVID_TTY = 1
DRVID_SCREEN = 2
DRVID_AUX = 4

DRVSTRUCT_ID    = 0
DRVSTRUCT_STRAT = 2
DRVSTRUCT_NEXT  = 4
DRVSTRUCT_NAME  = 6

TTY_CONST = 0
TTY_CONIN = 1
TTY_CONOUT = 2

AUX_IN = 0
AUX_OUT = 1
AUX_OPEN = 2
AUX_CLOSE = 3

SCREEN_GETSIZE    = 1
SCREEN_CLEAR      = 2
SCREEN_SETCURSOR  = 3
SCREEN_GETCURSOR  = 4
SCREEN_PUTCHAR    = 5
SCREEN_PUTSTRING  = 6
SCREEN_GETCHAR    = 7
SCREEN_SHOWCURSOR = 8
SCREEN_SCROLLUP   = 9
SCREEN_SCROLLDOWN = 10
SCREEN_CLEARTOEOL = 11
SCREEN_SETSTYLE   = 12
\ vim: filetype=asm sw=4 ts=4 et


