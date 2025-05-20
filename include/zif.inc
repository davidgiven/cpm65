; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

.altmacro

.set zlabelcount, 0
.set zsp, 0

.set zloopsp, 0
.set zifsp, 0

.macro zproc name, sect=.text, binding=global
    .section \sect, "ax"
    .\binding \name
    \name:
.endm

.macro zlproc name, sect=.text, binding=global
    zproc \name, .text, local
.endm

.macro zendproc
    .if (zloopsp != 0) || (zifsp != 0)
        .error "Unclosed structure macro"
    .endif
.endm

.macro _zgetframe kind, sp
    .set ZF, \kind\sp
.endm

.macro _zframe kind, sp
    .set \kind\sp, zlabelcount
    .set zlabelcount, zlabelcount+1
    _zgetframe \kind, \sp
.endm

.macro _zset stack, sp, name, val
    .set .L\stack\()_\sp\()_\name, \val
.endm

.macro _zsetifnotset stack, sp, name, val
    .ifndef .L\stack\()_\sp\()_\name
        .set .L\stack\()_\sp\()_\name, \val
    .endif
.endm

.macro _zget stack, label, var, insn
    \insn .L\stack\()_\label\()_\var
.endm

.macro zloop
    .set zloopsp, zloopsp + 1
    _zframe zloopstack, %zloopsp
    _zset zloopstack, %ZF, continue, .
.endm

.macro zendloop
    _zgetframe zloopstack, %zloopsp
    _zget zloopstack, %ZF, continue, jmp
    _zset zloopstack, %ZF, break, .
    .set zloopsp, zloopsp - 1
.endm

.macro zrepeat
    .set zloopsp, zloopsp + 1
    _zframe zloopstack, %zloopsp
    _zset zloopstack, %ZF, continue, .
.endm

.macro zcontinue
    _zgetframe zloopstack, %zloopsp
    _zget zloopstack, %ZF, continue, jmp
.endm

.macro _zmake_loops pos, neg
    .macro zbreakif_\pos
        _zgetframe zloopstack, %zloopsp
        _zget zloopstack, %ZF, break, b\pos
    .endm

    .macro zcontinueif_\pos
        _zgetframe zloopstack, %zloopsp
        _zget zloopstack, %ZF, continue, b\pos
    .endm

    .macro zuntil_\pos
        _zgetframe zloopstack, %zloopsp
        _zget zloopstack, %ZF, continue, b\neg
        _zset zloopstack, %ZF, break, .
        .set zloopsp, zloopsp - 1
    .endm
.endm

.macro zbreakif cond
    zbreakif_\cond
.endm

.macro zcontinueif cond
    zcontinueif_\cond
.endm

.macro zuntil cond
    zuntil_\cond
.endm

_zmake_loops eq, ne
_zmake_loops ne, eq
_zmake_loops lt, ge
_zmake_loops ge, lt
_zmake_loops cc, cs
_zmake_loops cs, cc
_zmake_loops pl, mi
_zmake_loops mi, pl
_zmake_loops vs, vc
_zmake_loops vc, vs

.macro _zmake_if pos, neg
    .macro zif_\pos
        .set zifsp, zifsp + 1
        _zframe zifstack, %zifsp
        _zget zifstack, %ZF, false, b\neg
    .endm
.endm

.macro zif cond, target
    zif_\cond \target
.endm

_zmake_if eq, ne
_zmake_if ne, eq
_zmake_if lt, ge
_zmake_if ge, lt
_zmake_if cc, cs
_zmake_if cs, cc
_zmake_if pl, mi
_zmake_if mi, pl
_zmake_if vs, vc
_zmake_if vc, vs

.macro zelse
    _zgetframe zifstack, %zifsp
    _zget zifstack, %ZF, end, jmp
    _zset zifstack, %ZF, false, .
.endm
    
.macro zendif
    _zgetframe zifstack, %zifsp
    _zsetifnotset zifstack, %ZF, false, .
    _zset zifstack, %ZF, end, .
    .set zifsp, zifsp - 1
.endm

; vim: filetype=asm sw=4 ts=4 et

