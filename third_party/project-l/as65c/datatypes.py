###################################################
#   Data types for as65c assembler
#      by MrL314
#
#        [ Aug.19, 2020 ]
###################################################


global LABEL
LABEL = "lbl"

global EXTERNAL
EXTERNAL = "ext"

global GLOBAL
GLOBAL = "glb"

global EQU
EQU = "equ"

global INCLUDE
INCLUDE = "incl"


global EXPRESSION
EXPRESSION = "expr"


global OPERATOR
OPERATOR = "oper"


global VALUE
VALUE = "val"

global CONST
CONST = "const"

global SEPARATOR
SEPARATOR = "sep"

global OPCODE
OPCODE = "op"


global INDIRECT_START
INDIRECT_START = "indir_s"

global INDIRECT_LONG_START
INDIRECT_LONG_START = "indirl_s"

global INDIRECT_END
INDIRECT_END = "indir_e"

global INDIRECT_LONG_END
INDIRECT_LONG_END = "indirl_e"


global CONDITIONAL_IF
CONDITIONAL_IF = "if"

global CONDITIONAL_ENDIF
CONDITIONAL_ENDIF = "endif"

global CONDITIONAL_ELSE
CONDITIONAL_ELSE = "else"

global CONDITION
CONDITION = "cond"


global REGISTER
REGISTER = "reg"


global TYPE
TYPE = "type"

global SECTION
SECTION = "sect"

global GROUP
GROUP = "grp"

global ORG
ORG = "org"

global DATA_BANK
DATA_BANK = "dbank"

global DATA_PAGE
DATA_PAGE = "dpage"


global END 
END = "end"

global PFLAG
PFLAG = "pflag"


global DBYTE
DBYTE = "db"

global DWORD
DWORD = "dw"

global DLONG
DLONG = "dl"



global VARIABLE
VARIABLE = "var"

global PSEG
PSEG = "pseg"

global DSEG
DSEG = "dseg"

global COMN
COMN = "comn"






global NEARVAR
NEARVAR = "nearvar"

global NORMALVAR
NORMALVAR = "normvar"


global RAW_BYTES
RAW_BYTES = "rawbytes"



global STORAGE_DIRECTIVE
STORAGE_DIRECTIVE = "S_DIR"


global MACRO
MACRO = "macro"

global MACRO_LOCAL
MACRO_LOCAL = "macro_local"

global END_MACRO
END_MACRO = "end_macro"