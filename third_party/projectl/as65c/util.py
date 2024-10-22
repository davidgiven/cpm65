###################################################
#   Helper data and functions for as65c assembler
#      by MrL314
#
#        [ Dec.4, 2021 ]
###################################################









# standard imports


# local imports
import exceptions
global DATA_TYPES
import datatypes as DATA_TYPES
import helpers as HELPER



# global export variables
global BSR_CHAR
global BSL_CHAR
global BANK_CHAR
global OFFSET_CHAR
global HIGH_CHAR
global LOW_CHAR
global M_VAR_CHAR_A
global M_VAR_CHAR_B
global M_LOC_CHAR
global M_SUB_CHAR_A
global M_SUB_CHAR_B
global ARITHMETIC_SYMBOLS
global OPCODE_SYMBOLS
global REGA_SYMBOLS
global REGX_SYMBOLS
global REGY_SYMBOLS
global REGS_SYMBOLS
global REGISTER_SYMBOLS
global SEPARATOR_SYMBOLS
global TYPE_SYMBOLS
global GLOBAL_SYMBOLS
global EXTERNAL_SYMBOLS
global INCLUDE_SYMBOLS
global SECTION_SYMBOLS
global PSEG_SYMBOLS
global DSEG_SYMBOLS
global COMN_SYMBOLS
global GROUP_SYMBOLS
global ORG_SYMBOLS
global DBANK_SYMBOLS
global DPAGE_SYMBOLS
global END_SYMBOLS
global PROCESSOR_SYMBOLS
global EQU_SYMBOLS
global BYTE_SYMBOLS
global WORD_SYMBOLS
global LONG_SYMBOLS
global DATA_SYMBOLS
global STORAGE_DIRECTIVE_SYMBOLS
global MACRO_SYMBOLS
global END_MACRO_SYMBOLS
global OTHER_SYMBOLS
global HASH_SYMBOLS
global PARSING_SYMBOLS
global RESERVED
global RESERVED_FLAT
global NONE

global PARSE_TYPES
global CONVERT_DATA_TYPE
global CONVERT_REGISTER

global OP_FORMATS





def flatten_list(L): return HELPER.flatten_list(L)

def flatten_set(L): return HELPER.flatten_set(L)

def size_to_bytes(size): return HELPER.size_to_bytes(size)

def get_symbols(file): return HELPER.get_symbols(file)

def set_symbols(symbols, file): return HELPER.set_symbols(symbols, file)

def load_hashes(): return HELPER.load_hashes()

def add_hash(file_hash, data_hash): return HELPER.add_hash(file_hash, data_hash)

def get_hash(file_hash): return HELPER.get_hash(file_hash)

def get_time(): return HELPER.get_time()




##########################################################
# make these symbols that the user could not enter unless intentionally 
#   trying to break things... (please don't)
# TO-DO: Pre-check to make sure that these symbols are never used in the raw text

# bit shift operation symbols
BSL_CHAR = "«"         # ALT + 174
BSR_CHAR = "»"         # ALT + 175

# bank/offset symbols
BANK_CHAR = "¶"        # ALT + 20
OFFSET_CHAR = "§"      # ALT + 21
HIGH_CHAR = "⌠"        # ALT + 244
LOW_CHAR = "⌡"         # ALT + 245

# macro variable symbol (only temporarily used!)
#M_VAR_CHAR_A = "%°"    # % +   ALT + 248
M_VAR_CHAR_A = "{%"    # { + %
M_VAR_CHAR_B = "}"     # }
M_LOC_CHAR = "˜"     # ALT + 0152

# near variable designator symbol




##########################################################


# macro substitution bracket symbol (only temporarily used!)
M_SUB_CHAR_A = "{"
M_SUB_CHAR_B = "}"





# symbols used in simple arithmetic in code
#ARITHMETIC_SYMBOLS = ("+", "-", "*", "/", "%", BSL_CHAR, BSR_CHAR, "|", "&", "^", "(", ")")
ARITHMETIC_SYMBOLS = {"+", "-", "*", "/", "%", BSL_CHAR, BSR_CHAR, "|", "&", "^", "(", ")"}

# symbols for separators
#SEPARATOR_SYMBOLS = ("(", ")", "[", "]", ",")
SEPARATOR_SYMBOLS = {"(", ")", "[", "]", ","}

# symbols for opcodes
#OPCODE_SYMBOLS = ("adc", "ADC", "and", "AND", "asl", "ASL", "bcc", "BCC", "blt", "BLT", "bcs", "BCS", "bge", "BGE", "beq", "BEQ", "bit", "BIT", "bmi", "BMI", "bne", "BNE", "bpl", "BPL", "bra", "BRA", "brk", "BRK", "brl", "BRL", "bvc", "BVC", "bvs", "BVS", "clc", "CLC", "cld", "CLD", "cli", "CLI", "clv", "CLV", "cmp", "CMP", "cop", "COP", "cpx", "CPX", "cpy", "CPY", "dec", "DEC", "dea", "DEA", "dex", "DEX", "dey", "DEY", "eor", "EOR", "inc", "INC", "ina", "INA", "inx", "INX", "iny", "INY", "jmp", "JMP", "jml", "JML", "jsr", "JSR", "jsl", "JSL", "lda", "LDA", "ldx", "LDX", "ldy", "LDY", "lsr", "LSR", "mvn", "MVN", "mvp", "MVP", "nop", "NOP", "ora", "ORA", "pea", "PEA", "pei", "PEI", "per", "PER", "pha", "PHA", "phb", "PHB", "phd", "PHD", "phk", "PHK", "php", "PHP", "phx", "PHX", "phy", "PHY", "pla", "PLA", "plb", "PLB", "pld", "PLD", "plp", "PLP", "plx", "PLX", "ply", "PLY", "rep", "REP", "rol", "ROL", "ror", "ROR", "rti", "RTI", "rtl", "RTL", "rts", "RTS", "sbc", "SBC", "sec", "SEC", "sed", "SED", "sei", "SEI", "sep", "SEP", "sta", "STA", "stp", "STP", "stx", "STX", "sty", "STY", "stz", "STZ", "tax", "TAX", "tay", "TAY", "tcd", "TCD", "tcs", "TCS", "tdc", "TDC", "trb", "TRB", "tsb", "TSB", "tsc", "TSC", "tsx", "TSX", "txa", "TXA", "txs", "TXS", "txy", "TXY", "tya", "TYA", "tyx", "TYX", "wai", "WAI", "wdm", "WDM", "xba", "XBA", "xce", "XCE")
OPCODE_SYMBOLS = {"adc", "ADC", "and", "AND", "asl", "ASL", "bcc", "BCC", "blt", "BLT", "bcs", "BCS", "bge", "BGE", "beq", "BEQ", "bit", "BIT", "bmi", "BMI", "bne", "BNE", "bpl", "BPL", "bra", "BRA", "brk", "BRK", "brl", "BRL", "bvc", "BVC", "bvs", "BVS", "clc", "CLC", "cld", "CLD", "cli", "CLI", "clv", "CLV", "cmp", "CMP", "cop", "COP", "cpx", "CPX", "cpy", "CPY", "dec", "DEC", "dea", "DEA", "dex", "DEX", "dey", "DEY", "eor", "EOR", "inc", "INC", "ina", "INA", "inx", "INX", "iny", "INY", "jmp", "JMP", "jml", "JML", "jsr", "JSR", "jsl", "JSL", "lda", "LDA", "ldx", "LDX", "ldy", "LDY", "lsr", "LSR", "mvn", "MVN", "mvp", "MVP", "nop", "NOP", "ora", "ORA", "pea", "PEA", "pei", "PEI", "per", "PER", "pha", "PHA", "phb", "PHB", "phd", "PHD", "phk", "PHK", "php", "PHP", "phx", "PHX", "phy", "PHY", "pla", "PLA", "plb", "PLB", "pld", "PLD", "plp", "PLP", "plx", "PLX", "ply", "PLY", "rep", "REP", "rol", "ROL", "ror", "ROR", "rti", "RTI", "rtl", "RTL", "rts", "RTS", "sbc", "SBC", "sec", "SEC", "sed", "SED", "sei", "SEI", "sep", "SEP", "sta", "STA", "stp", "STP", "stx", "STX", "sty", "STY", "stz", "STZ", "tax", "TAX", "tay", "TAY", "tcd", "TCD", "tcs", "TCS", "tdc", "TDC", "trb", "TRB", "tsb", "TSB", "tsc", "TSC", "tsx", "TSX", "txa", "TXA", "txs", "TXS", "txy", "TXY", "tya", "TYA", "tyx", "TYX", "wai", "WAI", "wdm", "WDM", "xba", "XBA", "xce", "XCE"}
OPCODE_REGS = {
	"adc": "a", 
	"and": "a", 
	"asl": " ", 
	"bcc": " ", 
	"blt": " ", 
	"bcs": " ", 
	"bge": " ", 
	"beq": " ", 
	"bit": "a", 
	"bmi": " ", 
	"bne": " ", 
	"bpl": " ", 
	"bra": " ", 
	"brk": " ", 
	"brl": " ", 
	"bvc": " ", 
	"bvs": " ", 
	"clc": " ", 
	"cld": " ", 
	"cli": " ",
	"clv": " ", 
	"cmp": "a", 
	"cop": "p", 
	"cpx": "x", 
	"cpy": "y", 
	"dec": " ", 
	"dea": " ", 
	"dex": " ", 
	"dey": " ", 
	"eor": "a", 
	"inc": " ", 
	"ina": " ", 
	"inx": " ", 
	"iny": " ", 
	"jmp": " ", 
	"jml": " ", 
	"jsr": " ", 
	"jsl": " ", 
	"lda": "a", 
	"ldx": "x", 
	"ldy": "y", 
	"lsr": " ", 
	"mvn": " ", 
	"mvp": " ", 
	"nop": " ", 
	"ora": "a", 
	"pea": "s", 
	"pei": " ", 
	"per": " ", 
	"pha": " ", 
	"phb": " ", 
	"phd": " ", 
	"phk": " ",
	"php": " ", 
	"phx": " ", 
	"phy": " ", 
	"pla": " ", 
	"plb": " ", 
	"pld": " ", 
	"plp": " ", 
	"plx": " ", 
	"ply": " ", 
	"rep": "p", 
	"rol": " ", 
	"ror": " ", 
	"rti": " ", 
	"rtl": " ", 
	"rts": " ", 
	"sbc": "a", 
	"sec": " ", 
	"sed": " ", 
	"sei": " ", 
	"sep": "p", 
	"sta": " ", 
	"stp": " ", 
	"stx": " ", 
	"sty": " ", 
	"stz": " ", 
	"tax": " ", 
	"tay": " ", 
	"tcd": " ", 
	"tcs": " ", 
	"tdc": " ", 
	"trb": " ", 
	"tsb": " ", 
	"tsc": " ", 
	"tsx": " ", 
	"txa": " ", 
	"txs": " ", 
	"txy": " ", 
	"tya": " ", 
	"tyx": " ", 
	"wai": " ", 
	"wdm": " ", 
	"xba": " ", 
	"xce": " "}

# symbols for a register
#REGA_SYMBOLS = ("a", "acc", "accumulator", "accum", "A", "ACC", "ACCUMULATOR", "ACCUM")
#REGA_SYMBOLS = ("a", "A")
REGA_SYMBOLS = {"a", "A"}


# symbols for x register
#REGX_SYMBOLS = ("x", "X")
REGX_SYMBOLS = {"x", "X"}

# symbols for y register
#REGY_SYMBOLS = ("y", "Y")
REGY_SYMBOLS = {"y", "Y"}

# symbols for stack register
#REGS_SYMBOLS = ("s", "stack", "S", "STACK")
#REGS_SYMBOLS = ("s", "S")
REGS_SYMBOLS = {"s", "S"}

# symbols for registers
#REGISTER_SYMBOLS = flatten_set((REGA_SYMBOLS, REGX_SYMBOLS, REGY_SYMBOLS, REGS_SYMBOLS))
REGISTER_SYMBOLS = set(flatten_list((REGA_SYMBOLS, REGX_SYMBOLS, REGY_SYMBOLS, REGS_SYMBOLS)))



# symbols for data types
#TYPE_SYMBOLS = ("<", ">", "!", "#", BANK_CHAR, OFFSET_CHAR, HIGH_CHAR, LOW_CHAR, "$")
#TYPE_SYMBOLS = {"<", ">", "!", "#", BANK_CHAR, OFFSET_CHAR, HIGH_CHAR, LOW_CHAR, "$"}
TYPE_SYMBOLS = {"<", ">", "!", "#", BANK_CHAR, OFFSET_CHAR, HIGH_CHAR, LOW_CHAR, "$"}


# symbols to declare global
#GLOBAL_SYMBOLS = ("glb", "global", "glob", "GLB", "GLOBAL", "GLOB")
GLOBAL_SYMBOLS = {"glb", "global", "glob", "GLB", "GLOBAL", "GLOB"}

# symbols to declare external
#EXTERNAL_SYMBOLS = ("ext", "external", "extern", "EXT", "EXTERNAL", "EXTERN")
EXTERNAL_SYMBOLS = {"ext", "external", "extern", "EXT", "EXTERNAL", "EXTERN"}

# symbols to declare include file
#INCLUDE_SYMBOLS = ("incl", "include", "INCL", "INCLUDE")
INCLUDE_SYMBOLS = {"incl", "include", "INCL", "INCLUDE"}



# symbols to declare section
#SECTION_SYMBOLS = ("sect", "section", "SECT", "SECTION")
SECTION_SYMBOLS = {"sect", "section", "SECT", "SECTION"}

# symbols to declare program section
#PSEG_SYMBOLS = ("prog", "program", "PROG", "PROGRAM")
PSEG_SYMBOLS = {"prog", "program", "PROG", "PROGRAM"}

# symbols to declare data section
#DSEG_SYMBOLS = ("data", "DATA")
DSEG_SYMBOLS = {"data", "DATA"}

# symbols to declare common section
#COMN_SYMBOLS = ("comn", "common", "COMN", "COMMON")
COMN_SYMBOLS = {"comn", "common", "COMN", "COMMON"}

# symbols to declare group
#GROUP_SYMBOLS = ("group", "grp", "GROUP", "GRP")
GROUP_SYMBOLS = {"group", "grp", "GROUP", "GRP"}

# symbols to declare org section
#ORG_SYMBOLS = ("org", "ORG")
ORG_SYMBOLS = {"org", "ORG"}


# symbols to declare data bank
#DBANK_SYMBOLS = ("dbank", "databank", "DBANK", "DATABANK")
DBANK_SYMBOLS = {"dbank", "databank", "DBANK", "DATABANK"}


# symbols to declare data page
#DPAGE_SYMBOLS = ("dpage", "datapage", "DPAGE", "DATAPAGE")
DPAGE_SYMBOLS = {"dpage", "datapage", "DPAGE", "DATAPAGE"}

# symbols to declare end
#END_SYMBOLS = ("end", "END")
END_SYMBOLS = {"end", "END"}


# symbols for processor flags
#PROCESSOR_SYMBOLS = ("mem8", "mem16", "idx8", "idx16", "MEM8", "MEM16", "IDX8", "IDX16")
PROCESSOR_SYMBOLS = {"mem8", "mem16", "idx8", "idx16", "native", "emulation", "MEM8", "MEM16", "IDX8", "IDX16", "NATIVE", "EMULATION"}


# symbols to declare variable value
#EQU_SYMBOLS = ("equ", "equal", "equals", "EQU", "EQUAL", "EQUALS")
EQU_SYMBOLS = {"equ", "equal", "equals", "EQU", "EQUAL", "EQUALS"}



# symbols to declare byte data
#BYTE_SYMBOLS = ("byte", "bytes", "db", "ascii", "BYTE", "BYTES", "DB", "ASCII")
BYTE_SYMBOLS = {"byte", "bytes", "db", "ascii", "BYTE", "BYTES", "DB", "ASCII"}

# symbols to declare word data
#WORD_SYMBOLS = ("word", "words", "dw", "WORD", "WORDS", "DW")
WORD_SYMBOLS = {"word", "words", "dw", "WORD", "WORDS", "DW"}

# symbols to declare long data
#LONG_SYMBOLS = ("long", "longs", "dl", "lword", "LONG", "LONGS", "DL", "LWORD")
LONG_SYMBOLS = {"long", "longs", "dl", "lword", "LONG", "LONGS", "DL", "LWORD"}

# symbols to indicate hex data list
#HEX_LIST_SYMBOLS = ("hex", "HEX")
HEX_LIST_SYMBOLS = {"hex", "HEX"}

# symbols to indicate binary data list
#BIN_LIST_SYMBOLS = ("bin", "BIN")
BIN_LIST_SYMBOLS = {"bin", "BIN"}


# symbols to declare data
#DATA_SYMBOLS = flatten_set((LONG_SYMBOLS, WORD_SYMBOLS, BYTE_SYMBOLS, HEX_LIST_SYMBOLS, BIN_LIST_SYMBOLS ))
DATA_SYMBOLS = set(flatten_list((LONG_SYMBOLS, WORD_SYMBOLS, BYTE_SYMBOLS, HEX_LIST_SYMBOLS, BIN_LIST_SYMBOLS )))



# symbols that affect compilation flow
#CONDITIONAL_SYMBOLS = ("if", "endif", "IF", "ENDIF")
CONDITIONAL_SYMBOLS = {"if", "endif", "else", "IF", "ENDIF", "ELSE"}

# symbols that signal storage directive
#STORAGE_DIRECTIVE_SYMBOLS = ("ds", "DS")
STORAGE_DIRECTIVE_SYMBOLS = {"ds", "DS"}

# symbols that signal a macro
#MACRO_SYMBOLS = ("macro", "MACRO")
MACRO_SYMBOLS = {"macro", "MACRO"}

# symbols that signal end of macro
#END_MACRO_SYMBOLS = ("endm", "ENDM")
END_MACRO_SYMBOLS = {"endm", "ENDM"}

# symbols that signal a local variable
#MACRO_LOCAL_SYMBOLS = ("local", "LOCAL")
MACRO_LOCAL_SYMBOLS = {"local", "LOCAL"}

# symbols that arent compiled but I don't know what to do with them yet
#OTHER_SYMBOLS = ("extend", "list", "nolist", "rel", "sall", "xall", "EXTEND", "LIST", "NOLIST", "REL", "SALL", "XALL")
OTHER_SYMBOLS = {"extend", "list", "nolist", "nlist", "rel", "sall", "xall", "EXTEND", "LIST", "NOLIST", "NLIST", "REL", "SALL", "XALL"}


# symbols that are important to checking the hash of the built file
#HASH_SYMBOLS = set(flatten_list((CONDITIONAL_SYMBOLS, MACRO_SYMBOLS, END_MACRO_SYMBOLS, INCLUDE_SYMBOLS )))
HASH_SYMBOLS = set()


# list of symbols used in parsing the data
#PARSING_SYMBOLS = flatten_set((SEPARATOR_SYMBOLS, ARITHMETIC_SYMBOLS))
PARSING_SYMBOLS = set(flatten_list((SEPARATOR_SYMBOLS, ARITHMETIC_SYMBOLS, {"<", ">", "!", "#", " $", "\t$", ",$"})))

# list of reserved names
RESERVED_FLAT = set([x.lower() for x in flatten_list((
	REGISTER_SYMBOLS,    # register names
	PARSING_SYMBOLS,     # parsing
	OPCODE_SYMBOLS,      # opcode mnemonics
	TYPE_SYMBOLS,        # data types
	GLOBAL_SYMBOLS, EXTERNAL_SYMBOLS,               # global variables
	INCLUDE_SYMBOLS,                                # included files
	SECTION_SYMBOLS, GROUP_SYMBOLS, ORG_SYMBOLS,    # sections
	PSEG_SYMBOLS, DSEG_SYMBOLS, COMN_SYMBOLS,
	DBANK_SYMBOLS, DPAGE_SYMBOLS,                   # data bank/page
	END_SYMBOLS,               # end of sections
	PROCESSOR_SYMBOLS,         # processor flags
	EQU_SYMBOLS,               # variables
	DATA_SYMBOLS,              # data
	HEX_LIST_SYMBOLS,          # raw hex list
	CONDITIONAL_SYMBOLS,       # assembler flow conditionals
	STORAGE_DIRECTIVE_SYMBOLS, # storage directive symbols
	MACRO_SYMBOLS,
	END_MACRO_SYMBOLS,
	MACRO_LOCAL_SYMBOLS,
	OTHER_SYMBOLS              # other
	))])

RESERVED_FLAT1 = flatten_list((
	REGISTER_SYMBOLS,    # register names
	PARSING_SYMBOLS,     # parsing
	OPCODE_SYMBOLS,      # opcode mnemonics
	TYPE_SYMBOLS,        # data types
	GLOBAL_SYMBOLS, EXTERNAL_SYMBOLS,               # global variables
	INCLUDE_SYMBOLS,                                # included files
	SECTION_SYMBOLS, GROUP_SYMBOLS, ORG_SYMBOLS,    # sections
	PSEG_SYMBOLS, DSEG_SYMBOLS, COMN_SYMBOLS,
	DBANK_SYMBOLS, DPAGE_SYMBOLS,                   # data bank/page
	END_SYMBOLS,               # end of sections
	PROCESSOR_SYMBOLS,         # processor flags
	EQU_SYMBOLS,               # variables
	DATA_SYMBOLS,              # data
	HEX_LIST_SYMBOLS,          # raw hex list
	CONDITIONAL_SYMBOLS,       # assembler flow conditionals
	STORAGE_DIRECTIVE_SYMBOLS, # storage directive symbols
	MACRO_SYMBOLS,
	END_MACRO_SYMBOLS,
	MACRO_LOCAL_SYMBOLS,
	OTHER_SYMBOLS              # other
	))





'''
RESERVED_FLAT = {}

# this is for run-time purposes. speed up access by using dict hash speed rather than tuple speed
for x in flatten_list(RESERVED):
	RESERVED_FLAT[x] = 0
'''


NONE = None





# conversion from type into the opcode format
PARSE_TYPES = {
	DATA_TYPES.INDIRECT_START: "(",
	DATA_TYPES.INDIRECT_END: ")",
	DATA_TYPES.INDIRECT_LONG_START: "[",
	DATA_TYPES.INDIRECT_LONG_END: "]",
	DATA_TYPES.SEPARATOR: ",",
	DATA_TYPES.TYPE: "TYPE",
	DATA_TYPES.REGISTER: "REGISTER"
}

CONVERT_DATA_TYPE = {
	"dp": "dp",
	"sr": "sr",
	"addr": "addr",
	"long": "long",
	"#const": "#const",
	"bank": "#const",
	"offset": "#const",
	"high": "#const",
	"low": "#const",
	"const": "#const"
}

CONVERT_REGISTER = {
	"x": "x",
	"y": "y",
	"a": "a", 
	"s": "S"
}



# OPCODE FORMATS



ADC_FORMAT = {
	"( dp , x )":         0x61,
	"sr , S":             0x63,
	"dp":                 0x65,
	"[ dp ]":             0x67,
	"#const":             0x69,
	"addr":               0x6d,
	"long":               0x6f,
	"( dp ) , y":         0x71,
	"( dp )":             0x72,
	"( sr , S ) , y":     0x73,
	"dp , x":             0x75,
	"[ dp ] , y":         0x77,
	"addr , y":           0x79,
	"addr , x":           0x7d,
	"long , x":           0x7f
}

AND_FORMAT = {
	"( dp , x )":         0x21,
	"sr , S":             0x23,
	"dp":                 0x25,
	"[ dp ]":             0x27,
	"#const":             0x29,
	"addr":               0x2d,
	"long":               0x2f,
	"( dp ) , y":         0x31,
	"( dp )":             0x32,
	"( sr , S ) , y":     0x33,
	"dp , x":             0x35,
	"[ dp ] , y":         0x37,
	"addr , y":           0x39,
	"addr , x":           0x3d,
	"long , x":           0x3f
}

ASL_FORMAT = {
	"dp":                 0x06,
	"a":                  0x0a,
	"addr":               0x0e,
	"dp , x":             0x16,
	"addr , x":           0x1e
}

BIT_FORMAT = {
	"dp":                 0x24,
	"addr":               0x2c,
	"dp , x":             0x34,
	"addr , x":           0x3c,
	"#const":             0x89
}

CMP_FORMAT = {
	"( dp , x )":         0xc1,
	"sr , S":             0xc3,
	"dp":                 0xc5,
	"[ dp ]":             0xc7,
	"#const":             0xc9,
	"addr":               0xcd,
	"long":               0xcf,
	"( dp ) , y":         0xd1,
	"( dp )":             0xd2,
	"( sr , S ) , y":     0xd3,
	"dp , x":             0xd5,
	"[ dp ] , y":         0xd7,
	"addr , y":           0xd9,
	"addr , x":           0xdd,
	"long , x":           0xdf
}

CPX_FORMAT = {
	"#const":             0xe0,
	"dp":                 0xe4,
	"addr":               0xec
}

CPY_FORMAT = {
	"#const":             0xc0,
	"dp":                 0xc4,
	"addr":               0xcc
}

DEC_FORMAT = {
	"a":                  0x3a,
	"dp":                 0xc6,
	"addr":               0xce,
	"dp , x":             0xd6,
	"addr , x":           0xde
}

EOR_FORMAT = {
	"( dp , x )":         0x41,
	"sr , S":             0x43,
	"dp":                 0x45,
	"[ dp ]":             0x47,
	"#const":             0x49,
	"addr":               0x4d,
	"long":               0x4f,
	"( dp ) , y":         0x51,
	"( dp )":             0x52,
	"( sr , S ) , y":     0x53,
	"dp , x":             0x55,
	"[ dp ] , y":         0x57,
	"addr , y":           0x59,
	"addr , x":           0x5d,
	"long , x":           0x5f
}

INC_FORMAT = {
	"a":                  0x1a,
	"dp":                 0xe6,
	"addr":               0xee,
	"dp , x":             0xf6,
	"addr , x":           0xfe
}

JMP_FORMAT = {
	"addr":               0x4c,
	"long":               0x5c,
	"( addr )":           0x6c,
	"( addr , x )":       0x7c,
	"[ addr ]":           0xdc
}

JML_FORMAT = {
	"long":               0x5c,
	"[ addr ]":           0xdc,
	"( addr )":           0xdc
}

JSR_FORMAT = {
	"addr":               0x20,
	"long":               0x22,
	"( addr , x )":       0xfc
}

JSL_FORMAT = {
	"long":               0x22
}

LDA_FORMAT = {
	"( dp , x )":         0xa1,
	"sr , S":             0xa3,
	"dp":                 0xa5,
	"[ dp ]":             0xa7,
	"#const":             0xa9,
	"addr":               0xad,
	"long":               0xaf,
	"( dp ) , y":         0xb1,
	"( dp )":             0xb2,
	"( sr , S ) , y":     0xb3,
	"dp , x":             0xb5,
	"[ dp ] , y":         0xb7,
	"addr , y":           0xb9,
	"addr , x":           0xbd,
	"long , x":           0xbf
}

LDX_FORMAT = {
	"#const":             0xa2,
	"dp":                 0xa6,
	"addr":               0xae,
	"dp , y":             0xb6,
	"addr , y":           0xbe
}

LDY_FORMAT = {
	"#const":             0xa0,
	"dp":                 0xa4,
	"addr":               0xac,
	"dp , x":             0xb4,
	"addr , x":           0xbc
}

LSR_FORMAT = {
	"dp":                 0x46,
	"a":                  0x4a,
	"addr":               0x4e,
	"dp , x":             0x56,
	"addr , x":           0x5e
}

ORA_FORMAT = {
	"( dp , x )":         0x01,
	"sr , S":             0x03,
	"dp":                 0x05,
	"[ dp ]":             0x07,
	"#const":             0x09,
	"addr":               0x0d,
	"long":               0x0f,
	"( dp ) , y":         0x11,
	"( dp )":             0x12,
	"( sr , S ) , y":     0x13,
	"dp , x":             0x15,
	"[ dp ] , y":         0x17,
	"addr , y":           0x19,
	"addr , x":           0x1d,
	"long , x":           0x1f
}

ROL_FORMAT = {
	"dp":                 0x26,
	"a":                  0x2a,
	"addr":               0x2e,
	"dp , x":             0x36,
	"addr , x":           0x3e
}

ROR_FORMAT = {
	"dp":                 0x66,
	"a":                  0x6a,
	"addr":               0x6e,
	"dp , x":             0x76,
	"addr , x":           0x7e
}

SBC_FORMAT = {
	"( dp , x )":         0xe1,
	"sr , S":             0xe3,
	"dp":                 0xe5,
	"[ dp ]":             0xe7,
	"#const":             0xe9,
	"addr":               0xed,
	"long":               0xef,
	"( dp ) , y":         0xf1,
	"( dp )":             0xf2,
	"( sr , S ) , y":     0xf3,
	"dp , x":             0xf5,
	"[ dp ] , y":         0xf7,
	"addr , y":           0xf9,
	"addr , x":           0xfd,
	"long , x":           0xff
}

STA_FORMAT = {
	"( dp , x )":         0x81,
	"sr , S":             0x83,
	"dp":                 0x85,
	"[ dp ]":             0x87,
	"addr":               0x8d,
	"long":               0x8f,
	"( dp ) , y":         0x91,
	"( dp )":             0x92,
	"( sr , S ) , y":     0x93,
	"dp , x":             0x95,
	"[ dp ] , y":         0x97,
	"addr , y":           0x99,
	"addr , x":           0x9d,
	"long , x":           0x9f
}

STX_FORMAT = {
	"dp":                 0x86,
	"addr":               0x8e,
	"dp , y":             0x96
}

STY_FORMAT = {
	"dp":                 0x84,
	"addr":               0x8c,
	"dp , x":             0x94
}

STZ_FORMAT = {
	"dp":                 0x64,
	"dp , x":             0x74,
	"addr":               0x9c,
	"addr , x":           0x9e
}

TRB_FORMAT = {
	"dp":                 0x14,
	"addr":               0x1c
}

TSB_FORMAT = {
	"dp":                 0x04,
	"addr":               0x0c
}

OP_FORMATS = {
	"ADC": ADC_FORMAT,
	"AND": AND_FORMAT,
	"ASL": ASL_FORMAT,
	"BIT": BIT_FORMAT,
	"CMP": CMP_FORMAT,
	"CPX": CPX_FORMAT,
	"CPY": CPY_FORMAT,
	"DEC": DEC_FORMAT,
	"EOR": EOR_FORMAT,
	"INC": INC_FORMAT,
	"JMP": JMP_FORMAT,
	"JML": JML_FORMAT,
	"JSR": JSR_FORMAT,
	"JSL": JSL_FORMAT,
	"LDA": LDA_FORMAT,
	"LDX": LDX_FORMAT,
	"LDY": LDY_FORMAT,
	"LSR": LSR_FORMAT,
	"ORA": ORA_FORMAT,
	"ROL": ROL_FORMAT,
	"ROR": ROR_FORMAT,
	"SBC": SBC_FORMAT,
	"STA": STA_FORMAT,
	"STX": STX_FORMAT,
	"STY": STY_FORMAT,
	"STZ": STZ_FORMAT,
	"TRB": TRB_FORMAT,
	"TSB": TSB_FORMAT
}



def get_formats(op):

	if op.upper() in OP_FORMATS:
		return OP_FORMATS[op.upper()]
	else:
		raise KeyError("opcode unrecognized")







def is_int(v):
	try:
		int(v)
		return True
	except:
		return False

op_tokens = "+-/*%&|^" + BSL_CHAR + BSR_CHAR
def is_func(t):
	if t in {"bank", "offset", "high", "low"}:
		return True
	return False

def is_operator(t):
	if t in op_tokens:
		return True
	if is_func(t):
		return True
	return False


def get_precedence(t):

	
	if t == "*" or t == "/" or t == "%":
		return 7
	elif t == "+" or t == "-":
		return 6
	elif t == BSL_CHAR or t == BSR_CHAR:
		return 5
	elif t == "&": 
		return 4
	elif t == "^":
		return 3
	elif t == "|":
		return 2
	elif is_func(t):
		return 1
	else:
		return 0




def evaluateExpression(EXP):

	E = EXP.replace("[", "(").replace("]", ")")
	E = " ".join(E.split()).split(" ")


	# convert infix to postfix via Shunting-yard algorithm
	output_queue = []
	operator_stack = []

	for tok in E:
		if is_int(tok):
			output_queue.append(tok)

		elif is_operator(tok):
			while operator_stack != []:
				if get_precedence(operator_stack[-1]) >= get_precedence(tok):
					if operator_stack[-1] != "(":
						output_queue.append(operator_stack.pop())
					else:
						break
				else:
					break

			operator_stack.append(tok)

		elif tok == "(":
			operator_stack.append(tok)

		elif tok == ")":
			while operator_stack != [] and operator_stack[-1] != "(":
				output_queue.append(operator_stack.pop())

			if operator_stack != []:
				if operator_stack[-1] == "(":
					operator_stack.pop()

	while operator_stack != []:
		output_queue.append(operator_stack.pop())


	# output_queue is now a postfix expression, which is easier to evaluate

	#print(output_queue, E)

	# postfix evaluation algorithm

	eval_stack = []

	for tok in output_queue:
		if is_int(tok):
			eval_stack.append(int(tok))

		elif is_func(tok):
			arg = eval_stack.pop()

			if tok == "bank":
				val = (arg // 0x10000) & 0xFF
			elif tok == "offset":
				val = arg & 0xFFFF
			elif tok == "high":
				val = (arg // 0x100) & 0xFF
			elif tok == "low":
				val = arg & 0xFF
			else:
				raise Exception("Bad expression " + " ".join(E))

			eval_stack.append(val)

		elif is_operator(tok):

			right_arg = eval_stack.pop()
			left_arg = eval_stack.pop()

			if tok == "+":
				val = left_arg + right_arg
			elif tok == "-":
				val = left_arg - right_arg
			elif tok == "*":
				val = left_arg * right_arg
			elif tok == "/":
				val = left_arg // right_arg
			elif tok == "%":
				val = left_arg % right_arg
			elif tok == "&":
				val = left_arg & right_arg
			elif tok == "|":
				val = left_arg | right_arg
			elif tok == "^":
				val = left_arg ^ right_arg
			elif tok == BSL_CHAR:
				val = left_arg << right_arg
			elif tok == BSR_CHAR:
				val = left_arg >> right_arg
			else:
				raise Exception("Bad expression " + " ".join(E))

			eval_stack.append(val)

		else:
			raise Exception("Bad expression " + " ".join(E))


	if len(eval_stack) == 1:
		return eval_stack[0]
	else:
		raise Exception("Error evaluating " + " ".join(E))




def is_digit(v):
	if v == "0": return True
	if v == "1": return True
	if v == "2": return True
	if v == "3": return True
	if v == "4": return True
	if v == "5": return True
	if v == "6": return True
	if v == "7": return True
	if v == "8": return True
	if v == "9": return True
	return False


def isValue(v, WARN=False):
	"""Returns true if the input is a type of value literal"""
	try:
		# if this works, the value is a decimal number
		int(v)
		return True
	except:
		pass
	
	try:
		if v[-1].lower() == "b":
			# if this works, the value is a binary number
			int("0b" + v[:-1], 2)

			if not is_digit(v[0]):
				if WARN: print("[DEBUG] REFUSING TO PARSE", str(v), "AS A BINARY VALUE. DEFAULTING TO A VARIABLE.")
				return False
			return True
		elif v[-1].lower() == "h":
			# if this works, the value is a hex number
			int("0x" + v[:-1], 16)

			if not is_digit(v[0]):
				if WARN: print("[DEBUG] REFUSING TO PARSE", str(v), "AS A HEX VALUE. DEFAULTING TO A VARIABLE.")
				return False
			return True
		else:
			# ascii char check
			if v[0] == "\"" and v[-1] == "\"" and len(v) == 3:
				return True
			elif v[0] == "\'" and v[-1] == "\'" and len(v) == 3:
				return True
			else:
				return False
	except:
		pass

	return False



def parseValue(v):
	"""Converts different types of values from string form into in integer""" 

	try:
		# if this works, the value is a decimal number
		return int(v)
	except:
		pass
	
	try:
		if v[-1].lower() == "b":
			# if this works, the value is a binary number
			return int("0b" + v[:-1], 2)
		elif v[-1].lower() == "h":
			# if this works, the value is a hex number
			return int("0x" + v[:-1], 16)
		else:
			# ascii char parse
			if v[0] == "\"" and v[-1] == "\"" and len(v) == 3:
				ch = v[1]
				if ch == "\x01":
					ch = " "
				return ord(ch)
			elif v[0] == "\'" and v[-1] == "\'" and len(v) == 3:
				ch = v[1]
				if ch == "\x01":
					ch = " "
				return ord(ch)
			else:
				raise TypeError("Invalid value type: " + str(type(v)) + " " + str(v))
	except:
		pass

	raise TypeError("Invalid value type: " + str(type(v)) + " " + str(v))












