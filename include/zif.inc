.macro zif_eq
	.scope
	bne zendif_label
.endmacro

.macro zif_ne
	.scope
	beq zendif_label
.endmacro

.macro zif_cc
	.scope
	bcs zendif_label
.endmacro

.macro zif_cs
	.scope
	bcc zendif_label
.endmacro

.macro zendif
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

.macro zbreak
	jmp zbreak_label
.endmacro

.macro zbreakif_eq
	beq zbreak_label
.endmacro

.macro zcontinueif_eq
	beq zloop_label
.endmacro

.macro zuntil_eq
	bne zloop_label
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

