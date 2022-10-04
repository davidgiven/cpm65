; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.macro zifbase
	.scope
	zhaselse .set 0
.endmacro

.macro zif_eq
	zifbase
	bne zfalse_label
.endmacro

.macro zif_ne
	zifbase
	beq zfalse_label
.endmacro

.macro zif_cc
	zifbase
	bcs zfalse_label
.endmacro

.macro zif_cs
	zifbase
	bcc zfalse_label
.endmacro

.macro zif_mi
	zifbase
	bpl zfalse_label
.endmacro

.macro zif_pl
	zifbase
	bmi zfalse_label
.endmacro

.macro zelse
	zhaselse .set 1
	jmp zendif_label
	zfalse_label:
.endmacro

.macro zendif
	.if zhaselse = 0
		zfalse_label:
	.endif
	zendif_label:
	.endscope
.endmacro

.macro zrepeat
	.scope
	zloop_label:
.endmacro

.macro zuntil_mi
	bpl zloop_label
	zbreak_label:
	.endscope
.endmacro

.macro zuntil_cs
	bcc zloop_label
	zbreak_label:
	.endscope
.endmacro

.macro zbreak
	jmp zbreak_label
.endmacro

.macro zbreakif_eq
	beq zbreak_label
.endmacro

.macro zbreakif_ne
	bne zbreak_label
.endmacro

.macro zbreakif_cs
	bcs zbreak_label
.endmacro

.macro zcontinueif_eq
	beq zloop_label
.endmacro

.macro zcontinue
	jmp zloop_label
.endmacro

.macro zuntil_eq
	bne zloop_label
	zbreak_label:
	.endscope
.endmacro

.macro zuntil_ne
	beq zloop_label
	zbreak_label:
	.endscope
.endmacro

.macro zuntil_cc
	bcs zloop_label
	zbreak_label:
	.endscope
.endmacro

.macro zloop
	.scope
	zloop_label:
.endmacro

.macro zendloop
	jmp zloop_label
	zbreak_label:
	.endscope
.endmacro

; vim: filetype=asm sw=4 ts=4 et

