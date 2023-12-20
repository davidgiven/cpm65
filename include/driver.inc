; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; 16-bit driver IDs.

#define DRVID_TTY    1
#define DRVID_SCREEN 2
#define DRVID_BLOCK  3
#define DRVID_AUX    4

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

; AUX driver entrypoints

#define AUX_IN  0  /* exit: C if no char pending, !C char in A */
#define AUX_OUT  1 /* exit: A=key */
#define AUX_OPEN  2 /*Open AUX channel */
#define AUX_CLOSE 3 /* Close AUX channel */



; SCREEN driver endpoints

; API version 0
#define SCREEN_VERSION     0 /* exit: A contains API version */

; Returns the current screen size.

#define SCREEN_GETSIZE     1 /* exit: A=width-1, X=height-1 */

; Clears the screen. The cursor position is left undefined.

#define SCREEN_CLEAR       2

; Sets the cursor position. Out of bounds coordinates produces undefined
; behaviour.

#define SCREEN_SETCURSOR   3 /* entry: A=x, X=y */

; Gets the cursor position.

#define SCREEN_GETCURSOR   4 /* exit: A=x, X=y */

; Writes a single printable character. Behaviour on writing non-printable
; characters is undefined. The cursor is moved one space to the right; if the
; cursor hits the edge of the screen, the behaviour is undefined.

#define SCREEN_PUTCHAR     5 /* entry: A=char */

; Writes a sequence of characters, equivalent to repeated calls to
; SCREEN_PUTCHAR (but hopefully a lot faster).

#define SCREEN_PUTSTRING   6 /* entry: XA=nul terminated pointer */

; Blocks and waits for a input character. XA contains a timeout in
; centiseconds. This call may return early.
; ESCAPE returns 27.
; DELETE returns 127 (not 8!).
; Control+Letter returns the usual codes from 1 to 26.

#define SCREEN_GETCHAR     7 /* entry: XA=timeout in cs, exit: A=char, or C if timed out */

; Sets whether the cursor is displayed or not.

#define SCREEN_SHOWCURSOR  8 /* entry: A=0 for off, non-zero for on */

; Scrolls the screen up by one line. The cursor position is left undefined.

#define SCREEN_SCROLLUP    9

; Scrolls the screen down by one line. The cursor position is left undefined.

#define SCREEN_SCROLLDOWN 10

; Clears from the current cursor position to the end of line. The cursor
; position is left undefined.

#define SCREEN_CLEARTOEOL 11

; Sets the style bitmap. If not supported, a platform will ignore a given
; style.
#define STYLE_REVERSE 1

#define SCREEN_SETSTYLE   12

; vim: filetype=asm sw=4 ts=4 et

