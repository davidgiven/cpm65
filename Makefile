export LLVM = /opt/pkg/llvm-mos/bin
export CC6502 = $(LLVM)/mos-cpm65-clang
export LD6502 = $(LLVM)/ld.lld
export AR6502 = $(LLVM)/llvm-ar

export CFLAGS6502 = -Os -g \
	-Wno-main-return-type

export OBJ = .obj

.PHONY: all
all: +all

TARGETS = +all +mametest
include build/ab.mk
