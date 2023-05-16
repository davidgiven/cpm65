; CP/M-65 Copyright © 2023 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; 16-bit driver IDs.

#define DRVID_TTY    1
#define DRVID_SCREEN 2
#define DRVID_BLOCK  3

; Driver management routine Y values.

#define DRVCMD_FIND  0 /* entry: XA=driver ID; exit: XA=strategy routine */
#define DRVCMD_NAME  1 /* exit: XA=pointer to string */
#define DRVCMD_NEXT  2 /* exit: XA=next management routine */

; vim: filetype=asm sw=4 ts=4 et

