; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; 16-bit driver IDs.

#define DRVID_TTY    1
#define DRVID_SCREEN 2
#define DRVID_BLOCK  3

; Driver structure:
;
;  +0  driver ID
;  +2  pointer to strategy routine
;  +4  pointer to next driver, or 0; filled in when added
;  +6  zero-terminated name starts here

#define DRVSTRUCT_ID    0
#define DRVSTRUCT_STRAT 2
#define DRVSTRUCT_NEXT  4
#define DRVSTRUCT_NAME  6

.macro defdriver name, id, strat, next=0
.data
.global drv_\name
drv_\name:
    .word \id
    .word \strat
    .word \next
    .ascii "\name"
    .byte 0
.endmacro

; TTY driver entrypoints

#define TTY_CONST  0 /* exit: C if no key pending, !C if key pending */
#define TTY_CONIN  1 /* exit: A=key */
#define TTY_CONOUT 2 /* entry: A=key */

; SCREEN driver endpoints

; API version 0
#define SCREEN_VERSION     0 /* exit: A contains API version */
#define SCREEN_GETSIZE     1 /* exit: A=width-1, X=height-1 */
#define SCREEN_CLEAR       2 /* also homes cursor */
#define SCREEN_SETCURSOR   3 /* entry: A=x, X=y; out of bounds undefined */
#define SCREEN_GETCURSOR   4 /* exit: A=x, X=y */
#define SCREEN_PUTCHAR     5 /* entry: A=char; moves cursor to right */
#define SCREEN_PUTSTRING   6 /* entry: XA=nul terminated pointer */
#define SCREEN_GETCHAR     7 /* entry: XA=timeoutin cs, exit: A=char, or C if timed out */
#define SCREEN_SHOWCURSOR  8 /* entry: A=0 for off, non-zero for on */
#define SCREEN_SCROLLUP    9 /* cursor position left undefined */
#define SCREEN_SCROLLDOWN 10 /* cursor position left undefined */
#define SCREEN_CLEARTOEOL 11 /* from cursor position to EOL */

; vim: filetype=asm sw=4 ts=4 et

