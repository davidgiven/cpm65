# Mad-Assembler http://mads.atari8.info
https://atariage.com/forums/topic/179559-mads-knowledge-base/#comments

MADS is a multi-pass crossassembler designed for 6502 and 65816 processors. Binaries are generated mainly for Atari 8-bit systems (supported are AtariDosII and SpartaDOS X formats).

MADS allows using macros and procedures (ability to use program stack), division of the memory between many virtual-banks, multi-dimensional names of labels (similar to C++ and Delphi languages), local-global-temporary labels.

Max. amount of labels and macros is limited to PC's memory size. Single listing's line can be 65536 bytes long and any label can be such long as well.

# Free Pascal Compiler http://www.freepascal.org/
# Compile: fpc -Mdelphi -vh -O3 mads.pas
