.macro zifeq
	.scope
	bne zendif_label
.endmacro

.macro zifne
	.scope
	beq zendif_label
.endmacro

.macro zendif
	zendif_label:
	.endscope
.endmacro

