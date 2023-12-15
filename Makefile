export LLVM = /opt/llvm-mos/bin
export CC6502 = $(LLVM)/mos-cpm65-clang
export AR6502 = $(LLVM)/llvm-ar
export CFLAGS6502 = -Os -g

export OBJ = .obj

.PHONY: all
all: +all

include build/ab.mk
