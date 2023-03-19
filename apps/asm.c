#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <cpm.h>
#include <ctype.h>
#include "lib/printi.h"

#define PACKED __attribute__((packed))

struct PACKED SymbolRecord;

typedef struct PACKED
{
    uint8_t descr;
} Record;

typedef struct PACKED
{
    Record record;
    uint8_t bytes[];
} ByteRecord;

typedef struct PACKED
{
    Record record;
    struct SymbolRecord* variable;
} LabelDefinitionRecord;

enum
{
    PP_NONE = 0,
    PP_LSB,
    PP_MSB,
};

typedef struct PACKED
{
    Record record;
    uint8_t opcode;
    struct SymbolRecord* variable;
    uint16_t offset;
    uint8_t length;
    uint8_t postprocessing;
} ExpressionRecord;

typedef struct PACKED SymbolRecord
{
    Record record;
    uint8_t type;
    struct SymbolRecord* variable;
    uint16_t offset;
    struct SymbolRecord* next;
    char name[];
} SymbolRecord;

typedef struct PACKED
{
    char name[3];
    uint8_t opcode;
    uint16_t addressingModes;
} Instruction;

#define lengthof(a) (sizeof(a) / sizeof(*a))

#define srcFcb cpm_fcb
#define inputBuffer ((char*)cpm_default_dma)
static char currentByte;
static uint8_t inputBufferPos = 128;
static FCB destFcb;
static uint8_t outputBuffer[128];
static uint8_t outputBufferPos;
static uint8_t* ramtop;
#define parseBuffer ((char*)outputBuffer)

static uint16_t lineNumber = 0;

static char token = 0;
static uint8_t tokenLength;
static uint16_t tokenValue;
static SymbolRecord* tokenVariable;
static uint8_t tokenPostProcessing;

static SymbolRecord* lastSymbol;

static uint8_t zpUsage = 0;
static uint16_t bssUsage = 0;
static uint16_t textUsage = 0;

#define START_ADDRESS 7

static uint8_t* top;

static int8_t relocationBuffer;

enum
{
    TOKEN_ID = 1,
    TOKEN_NUMBER = 2,
    TOKEN_STRING = 3,
    TOKEN_EOF = 26,
};

enum
{
    RECORD_EOF = 0 << 5,
    RECORD_BYTES = 1 << 5,
    RECORD_EXPR = 2 << 5,
    RECORD_SYMBOL = 3 << 5,
    RECORD_LABELDEF = 4 << 5,
};

enum
{
    SYMBOL_UNINITIALISED = 0,
    SYMBOL_REFERENCE,
    SYMBOL_ZP,
    SYMBOL_BSS,
    SYMBOL_TEXT,
    SYMBOL_COMPUTED,
};

typedef enum
{
    AM_XPTR = 1 << 0,  /* (0x12, x) */
    AM_ZP = 1 << 1,    /* 0x12 */
    AM_IMM = 1 << 2,   /* #0x12 */
    AM_ABS = 1 << 3,   /* 0x1234 */
    AM_YPTR = 1 << 4,  /* (0x12), y */
    AM_XOFZ = 1 << 5,  /* 0x12, x */
    AM_YOFF = 1 << 6,  /* 0x1234, y */
    AM_XOFF = 1 << 7,  /* 0x1234, x */
    AM_IMP = 1 << 8,   /* (nothing) */
    AM_A = 1 << 9,     /* A */
    AM_IMMS = 1 << 10, /* #0x12 */
    AM_WIND = 1 << 11, /* (0x1234) */
    AM_YOFZ = 1 << 12, /* 0x12, y */
} AddressingMode;

enum
{
    B_XPTR = 0 << 2,
    B_ZP = 1 << 2,
    B_IMM = 2 << 2,
    B_ABS = 3 << 2,
    B_YPTR = 4 << 2,
    B_XOFZ = 5 << 2,
    B_YOFF = 6 << 2,
    B_XOFF = 7 << 2,

    B_IMP = 8 << 2, /* not a real B-value */
    B_REL = 9 << 2, /* likewise */
};

enum
{
    BPROP_ZP = 1 << 0,
    BPROP_ABS = 1 << 1,
    BPROP_PTR = 1 << 2,
    BPROP_SHR = 1 << 3,
    BPROP_IMM = 1 << 4,
    BPROP_RELATIVE = 1 << 5,

    BPROP_SIZE_SHIFT = 6,
};

#define ILLEGAL 0xff

/* --- I/O --------------------------------------------------------------- */

static void cr(void)
{
    cpm_conout('\n');
    cpm_conout('\r');
}

static void printnl(const char* msg)
{
    cpm_printstring(msg);
    cr();
}

static void __attribute__((noreturn)) fatal(const char* msg)
{
    cpm_printstring("Error: ");
    if (lineNumber)
    {
        printi(lineNumber);
        cpm_printstring(": ");
    }
    printnl(msg);
    cpm_warmboot();
}

static void consumeByte()
{
    if (inputBufferPos == 128)
    {
        cpm_set_dma(inputBuffer);
        int i = cpm_read_sequential(&srcFcb);
        if (i != 0)
            currentByte = 26;
        inputBufferPos = 0;
    }

    currentByte = inputBuffer[inputBufferPos++];
}

static void flushOutputBuffer()
{
    cpm_set_dma(outputBuffer);
    cpm_write_sequential(&destFcb);
}

static void writeByte(uint8_t b)
{
    if (outputBufferPos == 128)
    {
        flushOutputBuffer();
        outputBufferPos = 0;
    }

    outputBuffer[outputBufferPos++] = b;
}

/* --- Lexer ------------------------------------------------------------- */

static int ishex(int c)
{
    char ch = (char)c;
    return ((ch >= 'A') && (ch <= 'F')) || ((ch >= 'a') && (ch <= 'f')) ||
           ((ch >= '0') && (ch <= '9'));
}

static void badEscape()
{
	fatal("bad escape");
}

static void consumeToken()
{
    tokenLength = 0;

    if (currentByte == 26)
    {
        token = currentByte;
        return;
    }

    for (;;)
    {
        if (currentByte == '\\')
        {
            do
                consumeByte();
            while ((currentByte != '\n') && (currentByte != 26));
        }
        else if ((currentByte == ' ') || (currentByte == '\t') ||
                 (currentByte == '\r'))
            consumeByte();
        else
            break;
    }

    if (currentByte == '\n')
    {
        lineNumber++;
        currentByte = ';';
    }

    switch (currentByte)
    {
        case 26:
        case '#':
        case ':':
        case ';':
        case ',':
        case '+':
        case '-':
        case '(':
        case ')':
        case '<':
        case '>':
        case '.':
        case '=':
        {
            token = currentByte;
            consumeByte();
            return;
        }
    }

    if (isalpha(currentByte) || (currentByte == '$'))
    {
        do
        {
            parseBuffer[tokenLength++] = currentByte;
            consumeByte();
        } while (isdigit(currentByte) || isalpha(currentByte));

        parseBuffer[tokenLength] = 0;
        token = TOKEN_ID;
        return;
    }

    if (isdigit(currentByte))
    {
        tokenValue = 0;
        uint8_t base = 10;

        if (currentByte == '0')
        {
            consumeByte();
            switch (currentByte)
            {
                case 'x':
                    base = 16;
                    consumeByte();
                    break;

                case 'b':
                    base = 2;
                    consumeByte();
                    break;

                case 'o':
                    base = 8;
                    consumeByte();
                    break;
            }
        }

        for (;;)
        {
            if (!ishex(currentByte))
                break;

            tokenValue *= base;

            uint8_t c = currentByte;
            if (c >= 'a')
                c = (c - 'a') + 10;
            else if (c >= 'A')
                c = (c - 'A') + 10;
            else
                c -= '0';
            if (c >= base)
                fatal("invalid number");
            tokenValue += c;

            consumeByte();
        }

        token = TOKEN_NUMBER;
        return;
    }

    if (currentByte == '"')
    {
		consumeByte();
        tokenLength = 0;
        for (;;)
        {
            char c = currentByte;
			consumeByte();
            if (c == '"')
                break;
            if (c == '\n')
                fatal("unterminated string constant");
            if (c == '\\')
            {
                c = currentByte;
                consumeByte();
                if (c == 'n')
                    c = 10;
                else if (c == 'r')
                    c = 13;
                else if (c == 't')
                    c = 9;
                else
					badEscape();
            }

            parseBuffer[tokenLength++] = c;
        }

        token = TOKEN_STRING;
        return;
    }

	if (currentByte == '\'')
	{
		consumeByte();
		if (currentByte == '\\')
		{
			consumeByte();
			switch (currentByte)
			{
				case 'n':
					currentByte = 10;
					break;

				case 'r':
					currentByte = 13;
					break;

				case 't':
					currentByte = 9;
					break;

				default:
					badEscape();
			}
		}

		tokenValue = currentByte;
		consumeByte();
		consumeByte();
		token = TOKEN_NUMBER;
		return;
	}

    fatal("bad parse");
}

/* --- Instruction data -------------------------------------------------- */

#define AM_ALU \
    (AM_XPTR | AM_ZP | AM_IMM | AM_ABS | AM_YPTR | AM_XOFZ | AM_XOFF | AM_YOFF)

static const Instruction simpleInsns[] = {
    {"ADC", 0x61, AM_ALU},
    {"AND", 0x21, AM_ALU},
    {"ASL", 0x02, AM_ZP | AM_A | AM_ABS | AM_XOFZ | AM_XOFF},
    {"BCC", 0x90, AM_ABS},
    {"BCS", 0xb0, AM_ABS},
    {"BEQ", 0xf0, AM_ABS},
    {"BIT", 0x24, AM_ZP | AM_ABS},
    {"BMI", 0x30, AM_ABS},
    {"BNE", 0xd0, AM_ABS},
    {"BPL", 0x10, AM_ABS},
    {"BRK", 0x00, AM_ABS},
    {"BVC", 0x50, AM_ABS},
    {"BVS", 0x70, AM_ABS},
    {"CLC", 0x18, AM_IMP},
    {"CLD", 0xd8, AM_IMP},
    {"CLI", 0x58, AM_IMP},
    {"CLV", 0xb8, AM_IMP},
    {"CMP", 0xc1, AM_ALU},
    {"CPX", 0xe0, AM_IMMS | AM_ZP | AM_ABS},
    {"CPY", 0xc0, AM_IMMS | AM_ZP | AM_ABS},
    {"DEX", 0xca, AM_IMP},
    {"DEY", 0x88, AM_IMP},
    {"EOR", 0x41, AM_ALU},
    {"INX", 0xe8, AM_IMP},
    {"INY", 0xc8, AM_IMP},
    {"JMP", 0x40, AM_ABS | AM_WIND},
    {"JSR", 0x20 - B_ABS, AM_ABS},
    {"LDA", 0xa1, AM_ALU},
    {"LDX", 0xa2, AM_IMMS | AM_ZP | AM_ABS | AM_YOFZ | AM_YOFF},
    {"LDY", 0xa0, AM_IMMS | AM_ZP | AM_ABS | AM_XOFZ | AM_XOFF},
    {"LSR", 0x42, AM_ZP | AM_A | AM_ABS | AM_XOFZ | AM_XOFF},
    {"NOP", 0xea, AM_IMP},
    {"ORA", 0x01, AM_ALU},
    {"PHA", 0x48, AM_IMP},
    {"PHP", 0x08, AM_IMP},
    {"PLA", 0x68, AM_IMP},
    {"PLP", 0x28, AM_IMP},
    {"ROL", 0x22, AM_ZP | AM_A | AM_ABS | AM_XOFZ | AM_XOFF},
    {"ROR", 0x62, AM_ZP | AM_A | AM_ABS | AM_XOFZ | AM_XOFF},
    {"RTI", 0x40, AM_IMP},
    {"RTS", 0x60, AM_IMP},
    {"SBC", 0xe1, AM_ALU},
    {"SEC", 0x38, AM_IMP},
    {"SED", 0xf8, AM_IMP},
    {"SEI", 0x78, AM_IMP},
    {"STA", 0x81, AM_ALU & ~AM_IMM},
    {"STX", 0x82, AM_ZP | AM_ABS | AM_YOFZ},
    {"STY", 0x80, AM_ZP | AM_ABS | AM_XOFZ},
    {"TAX", 0xaa, AM_IMP},
    {"TAY", 0xa8, AM_IMP},
    {"TSX", 0xba, AM_IMP},
    {"TXA", 0x8a, AM_IMP},
    {"TXS", 0x9a, AM_IMP},
    {"TYA", 0x98, AM_IMP},
    {}
};

static const uint8_t bOfAm[] = {
    B_XPTR,       /* AM_XPTR */
    B_ZP,         /* AM_ZP */
    B_IMM,        /* AM_IMM */
    B_ABS,        /* AM_ABS */
    B_YPTR,       /* AM_YPTR */
    B_XOFZ,       /* AM_XOFZ */
    B_YOFF,       /* AM_YOFF */
    B_XOFF,       /* AM_XOFF */
    0,            /* AM_IMP */
    2 << 2,       /* AM_A */
    0 << 2,       /* AM_IMMS */
    0x20 | B_ABS, /* AM_WIND */
    B_XOFZ,       /* AM_YOFZ */
};

static const Instruction* findInstruction(const Instruction* insn)
{
    char opcode[3];

    for (int i = 0; i < 3; i++)
        opcode[i] = toupper(parseBuffer[i]);

    while (insn->name[0])
    {
        if ((opcode[0] == insn->name[0]) && (opcode[1] == insn->name[1]) &&
            (opcode[2] == insn->name[2]))
        {
            return insn;
        }

        insn++;
    }

    return NULL;
}

static uint8_t getBofAM(uint16_t am)
{
    uint8_t p = 0;
    while (!(am & 1))
    {
        p++;
        am >>= 1;
    }
    return bOfAm[p];
}

static uint8_t getB(uint8_t opcode)
{
    if ((opcode & 0b00000011) == 0b00000001) /* c=1 */
    {
        /* Normal ALU block */

        return opcode & 0b00011100;
    }
    else if ((opcode & 0b00000011) == 0b00000010) /* c=2 */
    {
        /* Shift instructions with ALU-compatible b-values? */

        if (opcode & 0b00000100)
            return opcode & 0b00011100;

        /* ldx # is special */

        if (opcode == 0xa2)
            return B_IMM;

        return B_IMP;
    }
    else /* c=0 */
    {
        /* Misc instructions with ALU-compatible b-values? */

        if (opcode & 0b00000100)
            return opcode & 0b00011100;

        /* Relative branches? */

        if ((opcode & 0b00011100) == 0b00010000)
            return B_REL;

        /* JSR is special */

        if (opcode == 0x20)
            return B_ABS;

        /* LDY/CPX/CPY are special */

        if ((opcode & 0b10011100) == 0b10000000)
            return B_IMM;

        return B_IMP;
    }
}

static uint8_t getBProps(uint8_t b)
{
    static const uint8_t flags[] = {
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP | BPROP_PTR,  // B_XPTR
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP,              // B_ZP
        (2 << BPROP_SIZE_SHIFT) | BPROP_IMM,             // B_IMM
        (3 << BPROP_SIZE_SHIFT) | BPROP_ABS | BPROP_SHR, // B_ABS
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP | BPROP_PTR,  // B_YPTR
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP,              // B_XOFZ
        (3 << BPROP_SIZE_SHIFT) | BPROP_ABS,             // B_YOFF
        (3 << BPROP_SIZE_SHIFT) | BPROP_ABS | BPROP_SHR, // B_XOFF
        (1 << BPROP_SIZE_SHIFT),                         // B_IMP
        (2 << BPROP_SIZE_SHIFT) | BPROP_RELATIVE,        // B_REL
    };

    return flags[b >> 2];
}

static uint8_t getInsnProps(uint8_t opcode)
{
    return getBProps(getB(opcode));
}

static uint8_t getInsnLength(uint8_t opcode)
{
    return getInsnProps(opcode) >> BPROP_SIZE_SHIFT;
}

/* --- Record management ------------------------------------------------- */

static void* addRecord(uint8_t descr)
{
    Record* r = (Record*)top;
    if ((r->descr & 0xe0) == RECORD_BYTES)
    {
        uint8_t len = r->descr & 0x1f;
        top += len;
        r = (Record*)top;
    }

    r->descr = descr;
    top += descr & 0x1f;
    return r;
}

static void emitByte(uint8_t byte)
{
    ByteRecord* r = (ByteRecord*)top;
    if (((r->record.descr & 0xe0) != RECORD_BYTES) ||
        ((r->record.descr & 0x1f) == 0x1f))
    {
        r = addRecord(0 | RECORD_BYTES);
        r->record.descr++;
    }

    uint8_t len = r->record.descr & 0x1f;
    r->bytes[len - 1] = byte;
    r->record.descr++;
}

static void addExpressionRecord(uint8_t op)
{
    if (tokenVariable)
    {
        ExpressionRecord* r = addRecord(sizeof(ExpressionRecord) | RECORD_EXPR);
        r->opcode = op;
        r->variable = tokenVariable;
        r->offset = tokenValue;
        r->length = 0xff;
        r->postprocessing = tokenPostProcessing;
    }
    else
    {
        uint8_t len = getInsnLength(op);
        emitByte(op);
        if (len != 1)
        {
            emitByte(tokenValue & 0xff);
            if (len != 2)
                emitByte(tokenValue >> 8);
        }
    }
}

/* --- Symbol table management ------------------------------------------- */

static SymbolRecord* lookupSymbol()
{
    SymbolRecord* r = lastSymbol;
    while (r)
    {
        uint8_t len = (r->record.descr & 0x1f) - offsetof(SymbolRecord, name);
        if ((len == tokenLength) && (memcmp(parseBuffer, r->name, len) == 0))
            return r;

        r = r->next;
    }

    return NULL;
}

static SymbolRecord* appendSymbol()
{
    uint8_t len = tokenLength + offsetof(SymbolRecord, name);
    if (len > 0x1f)
        fatal("symbol too long");

    SymbolRecord* r = addRecord(RECORD_SYMBOL | len);
    memcpy(r->name, parseBuffer, tokenLength);
    r->next = lastSymbol;
    lastSymbol = r;
    return r;
}

static SymbolRecord* addOrFindSymbol()
{
    SymbolRecord* r = lookupSymbol();
    if (r)
        return r;

    return appendSymbol();
}

static void symbolExists()
{
    fatal("symbol exists");
}

static SymbolRecord* addSymbol()
{
    if (lookupSymbol())
        symbolExists();

    return appendSymbol();
}

/* --- Parser ------------------------------------------------------------ */

static void syntaxError()
{
    fatal("syntax error");
}

static void expect(char t)
{
    if (token != t)
        syntaxError();
}

static void consume(char t)
{
    expect(t);
    consumeToken();
}

static char consumeXorY()
{
    if ((token == TOKEN_ID) && (tokenLength == 1))
    {
        char c = toupper(parseBuffer[0]);
        if ((c == 'X') || (c == 'Y'))
        {
            consumeToken();
            return c;
        }
    }
    fatal("expected X or Y");
}

static void postProcessConstant()
{
    if (tokenVariable)
        return;

    switch (tokenPostProcessing)
    {
        case PP_LSB:
            tokenValue = tokenValue & 0xff;
            break;

        case PP_MSB:
            tokenValue = tokenValue >> 8;
            break;
    }
    tokenPostProcessing = PP_NONE;
}

static void consumeExpression()
{
    tokenVariable = NULL;
    tokenPostProcessing = PP_NONE;

    if (token == '<')
    {
        consumeToken();
        tokenPostProcessing = PP_LSB;
    }
    else if (token == '>')
    {
        consumeToken();
        tokenPostProcessing = PP_MSB;
    }

    switch (token)
    {
        case TOKEN_NUMBER:
            consumeToken();
            postProcessConstant();
            return;

        case TOKEN_ID:
        {
            SymbolRecord* r = addOrFindSymbol();
            if (r->type == SYMBOL_UNINITIALISED)
                r->type = SYMBOL_REFERENCE;

            uint16_t offset;
            if (r->type == SYMBOL_COMPUTED)
            {
                tokenVariable = r->variable;
                offset = r->offset;
            }
            else
            {
                tokenVariable = r;
                offset = 0;
            }

            consumeToken();
            if ((token == '+') || (token == '-'))
            {
                consumeToken();
                expect(TOKEN_NUMBER);
                if (token == '+')
                    offset += tokenValue;
                else
                    offset -= tokenValue;
                consumeToken();
            }
            tokenValue = offset;

            return;
        }

        default:
            syntaxError();
    }
}

static void consumeConstExpression()
{
    consumeExpression();
    if (tokenVariable)
        fatal("expression must be constant");
}

static AddressingMode consumeArgument()
{
    tokenValue = 0;
    tokenVariable = NULL;
    switch (token)
    {
        case '#':
            consumeToken();
            consumeExpression();
            return AM_IMM;

        case '(':
            consumeToken();
            consumeExpression();
            if (token == ')')
            {
                consumeToken();
                if (token != ',')
                    return AM_WIND;

                consumeToken();
                char c = consumeXorY();
                if (c != 'Y')
                    fatal("bad addressing mode");

                return AM_YPTR;
            }
            else
            {
                consume(',');
                char c = consumeXorY();
                if (c != 'X')
                    fatal("bad addressing mode");
                consume(')');

                return AM_XPTR;
            }

        case TOKEN_ID:
            if ((tokenLength == 1) && (toupper(parseBuffer[0]) == 'A'))
            {
                consumeToken();
                return AM_A;
            }
            /* fall through */
        case TOKEN_NUMBER:
            consumeExpression();
            if (token == ',')
            {
                consumeToken();
                char c = consumeXorY();
                if (c == 'X')
                {
                    if (!tokenVariable && (tokenValue < 0x100))
                        return AM_XOFZ;
                    else
                        return AM_XOFF;
                }
                else
                {
                    /* Must be Y */
                    if (!tokenVariable && (tokenValue < 0x100))
                        return AM_YOFZ;
                    else
                        return AM_YOFF;
                }
            }
            else if (!tokenVariable && (tokenValue < 0x100))
                return AM_ZP;
            else
                return AM_ABS;

        default:
            fatal("bad addressing mode");
    }
}

static SymbolRecord* consumeSymbolCommaNumber()
{
    expect(TOKEN_ID);
    SymbolRecord* r = addSymbol();

    expect(',');
    consumeConstExpression();
    return r;
}

static void consumeDotZp()
{
	consumeToken();
    SymbolRecord* r = consumeSymbolCommaNumber();
    if ((zpUsage + tokenValue) < zpUsage)
        fatal("ran out of zero page");

    r->type = SYMBOL_ZP;
    r->offset = zpUsage;
    zpUsage += tokenValue;
}

static void consumeDotBss()
{
	consumeToken();
    SymbolRecord* r = consumeSymbolCommaNumber();
    if ((bssUsage + tokenValue) < bssUsage)
        fatal("ran out of BSS");

    r->type = SYMBOL_BSS;
    r->offset = bssUsage;
    bssUsage += tokenValue;
}

static void consumeDotByte()
{
	consumeToken();
    for (;;)
    {
        if (token == TOKEN_STRING)
        {
            const char* p = parseBuffer;
            while (*p)
                emitByte(*p++);

            consumeToken();
        }
        else
        {
            consumeExpression();
            if (tokenVariable)
                addExpressionRecord(0x00);
            else
            {
                emitByte(tokenValue);
            }
        }

        if (token != ',')
            break;
        consumeToken();
    }
}

static void consumeDotWord()
{
	consumeToken();
    for (;;)
    {
        consumeExpression();
        if (tokenVariable)
            addExpressionRecord(0xff);
        else
        {
            emitByte(tokenValue & 0xff);
            emitByte(tokenValue >> 8);
        }

        if (token != ',')
            break;
        consumeToken();
    }
}

static void parse()
{
    top = cpm_ram;

    for (;;)
    {
        switch (token)
        {
            case TOKEN_EOF:
                goto exit;

            case ';':
                consumeToken();
                continue;

            case '.':
                consumeToken();
                expect(TOKEN_ID);
                if (strcmp(parseBuffer, "zp") == 0)
                    consumeDotZp();
                else if (strcmp(parseBuffer, "bss") == 0)
                    consumeDotBss();
                else if (strcmp(parseBuffer, "byte") == 0)
                    consumeDotByte();
                else if (strcmp(parseBuffer, "word") == 0)
                    consumeDotWord();
                else
                    fatal("unknown pseudo-op");
                break;

            case TOKEN_ID:
                /* Process instructions. */

                if (tokenLength == 3)
                {
                    /* Look up the instruction. */

                    const Instruction* insn = findInstruction(simpleInsns);
                    if (insn)
                    {
                        consumeToken();
                        if (insn->addressingModes & AM_IMP)
                        {
                            emitByte(insn->opcode);
                            break;
                        }

                        AddressingMode am = consumeArgument();
                        if ((insn->addressingModes & AM_IMMS) && (am == AM_IMM))
                            am = AM_IMMS;
                        if (!(insn->addressingModes & AM_YOFZ) &&
                            (am == AM_YOFZ))
                            am = AM_YOFF;
                        if (!(insn->addressingModes & AM_ZP) && (am == AM_ZP))
                            am = AM_ABS;
                        if (!(insn->addressingModes & am))
                            fatal("invalid addressing mode");

                        uint8_t op = insn->opcode;
                        if (!(getInsnProps(op) & BPROP_RELATIVE))
                            op += getBofAM(am);
                        addExpressionRecord(op);
                        break;
                    }
                }

                /* Not an instruction. Must be a symbol definition. */

                SymbolRecord* r = addOrFindSymbol();
                consumeToken();
                if (token == ':')
                {
                    if ((r->type != SYMBOL_UNINITIALISED) &&
                        (r->type != SYMBOL_REFERENCE))
                        symbolExists();
                    r->type = SYMBOL_TEXT;

                    LabelDefinitionRecord* r2 = addRecord(
                        sizeof(LabelDefinitionRecord) | RECORD_LABELDEF);
                    r2->variable = r;
                    consumeToken();
                    break;
                }
                else if (token == '=')
                {
                    if (r->type != SYMBOL_UNINITIALISED)
                        symbolExists();

                    consumeToken();
                    consumeExpression();
                    if (tokenPostProcessing != PP_NONE)
                        fatal("cannot postprocess value here");
                    if (tokenVariable)
                        r->variable = tokenVariable;
                    r->type = SYMBOL_COMPUTED;
                    r->offset = tokenValue;
                    break;
                }
                /* fall through */
            default:
                fatal("unexpected token");
        }

        if (token == 26)
            break;
        if (token != ';')
            fatal("unexpected garbage at end of line");
        consumeToken();
    }

exit:
    addRecord(1 | RECORD_EOF);
}

/* --- Code placement ---------------------------------------------------- */

static bool placeCode(uint8_t pass)
{
    bool changed = false;
    uint8_t* r = cpm_ram;
    uint16_t pc = START_ADDRESS;
    for (;;)
    {
        uint8_t type = *r & 0xe0;
        uint8_t len = *r & 0x1f;

        switch (type)
        {
            case RECORD_SYMBOL:
            {
                SymbolRecord* s = (SymbolRecord*)r;
                if (s->type == SYMBOL_REFERENCE)
                    fatal("unresolved forward reference");
                break;
            }

            case RECORD_BYTES:
                pc += len - offsetof(ByteRecord, bytes);
                break;

            case RECORD_EXPR:
            {
                ExpressionRecord* s = (ExpressionRecord*)r;
                uint8_t bprops = getInsnProps(s->opcode);
                uint8_t len = getInsnLength(s->opcode);

                if (s->opcode == 0x00)
                {
                    /* Magic value meaning a byte constant */

                    len = 1;
                }
                else if (s->opcode == 0xff)
                {
                    /* Magic value meaning a word constant */

                    len = 2;
                }
                else if (s->variable && (s->variable->type == SYMBOL_ZP) &&
                         (bprops & BPROP_SHR))
                {
                    /* Shrink anything which is pointing into zero page. */
                    s->opcode &= 0b11110111;
                    len = 2;
                }
                else if (bprops & BPROP_RELATIVE)
                {
                    if (!s->variable || (s->variable->type != SYMBOL_TEXT))
                        fatal("branch to non-text address");

                    if (pass == 0)
                        len = 5;
                    else
                    {
                        int delta = (s->variable->offset + s->offset) - pc;
                        if ((delta >= -128) && (delta <= 127))
                            len = 2;
                        else
                            len = 5;
                    }
                }

                if (len != s->length)
                {
                    s->length = len;
                    changed = true;
                }
                pc += len;
                break;
            }

            case RECORD_LABELDEF:
            {
                LabelDefinitionRecord* s = (LabelDefinitionRecord*)r;
                s->variable->offset = pc;
                break;
            }

            case RECORD_EOF:
                goto exit;
        }

        r += len;
    }

exit:
    textUsage = pc;
    return changed;
}

/* --- Code emission ----------------------------------------------------- */

static void writeCode()
{
    uint8_t* r = cpm_ram;
    uint8_t pc = START_ADDRESS;
    for (;;)
    {
        uint8_t type = *r & 0xe0;
        uint8_t len = *r & 0x1f;

        switch (type)
        {
            case RECORD_BYTES:
            {
                ByteRecord* s = (ByteRecord*)r;
                uint8_t count = len - offsetof(ByteRecord, bytes);
                for (uint8_t i = 0; i < count; i++)
                    writeByte(s->bytes[i]);
                pc += count;
                break;
            }

            case RECORD_EXPR:
            {
                ExpressionRecord* s = (ExpressionRecord*)r;
                uint8_t bprops = getInsnProps(s->opcode);

                if (bprops & BPROP_RELATIVE)
                {
                    uint16_t address = s->variable->offset + s->offset;
                    if (s->length == 2)
                    {
                        int delta = address - pc - 2;
                        writeByte(s->opcode);
                        writeByte(delta);
                    }
                    else
                    {
                        writeByte(s->opcode ^ 0b00100000);
                        writeByte(3);
                        writeByte(0x4c); /* JMP */
                        writeByte(address & 0xff);
                        writeByte(address >> 8);
                    }
                }
                else
                {
                    if ((s->opcode != 0x00) && (s->opcode != 0xff))
                        writeByte(s->opcode);

                    uint16_t address = s->offset;
                    if (s->variable)
                    {
                        address += s->variable->offset;
                        if (s->variable->type == SYMBOL_BSS)
                            address += textUsage;
                    }

                    if (s->postprocessing == PP_MSB)
                        address >>= 8;
                    else if (s->postprocessing == PP_LSB)
                        address &= 0xff;

                    writeByte(address & 0xff);
                    if ((s->length == 3) || (s->opcode == 0xff))
                        writeByte(address >> 8);
                }

                pc += s->length;
                break;
            }

            case RECORD_EOF:
                goto exit;
        }

        r += len;
    }

exit:;
}

static void writeHeader()
{
    writeByte(zpUsage);
    writeByte((textUsage + 255) >> 8);
    writeByte(textUsage & 0xff);
    writeByte(textUsage >> 8);
    writeByte(0x4c);
    writeByte(0);
    writeByte(0);
}

static void resetRelocationWriter()
{
    relocationBuffer = -1;
}

static void writeRelocation(uint8_t nibble)
{
    if (relocationBuffer == -1)
        relocationBuffer = nibble << 4;
    else
    {
        writeByte(relocationBuffer | nibble);
        relocationBuffer = -1;
    }
}

static void writeRelocationFor(uint16_t delta)
{
    while (delta >= 0xe)
    {
        writeRelocation(0xe);
        delta -= 0xe;
    }
    writeRelocation(delta);
}

static void flushRelocations()
{
    if (relocationBuffer != -1)
        writeRelocation(0);
}

static void writeTextRelocations()
{
    uint8_t* r = cpm_ram;
    uint16_t pc = START_ADDRESS;
    uint16_t lastRelocation = 0;
    resetRelocationWriter();

    for (;;)
    {
        uint8_t type = *r & 0xe0;
        uint8_t len = *r & 0x1f;

        switch (type)
        {
            case RECORD_BYTES:
                pc += len - offsetof(ByteRecord, bytes);
                break;

            case RECORD_EXPR:
            {
                ExpressionRecord* s = (ExpressionRecord*)r;
                uint8_t len = s->length;
                if ((s->postprocessing != PP_LSB) && s->variable &&
                    ((s->variable->type == SYMBOL_TEXT) ||
                        (s->variable->type == SYMBOL_BSS)))
                {
                    uint8_t bprops = getInsnProps(s->opcode);
                    if (!(bprops & BPROP_RELATIVE) || (len != 2))
                    {
                        uint16_t address = pc + len - 1;
                        if (s->postprocessing == PP_MSB)
                        {
                            if (!(bprops & BPROP_IMM))
                                address--;
                        }

                        writeRelocationFor(address - lastRelocation);
                        lastRelocation = address;
                    }
                }
                pc += len;
                break;
            }

            case RECORD_EOF:
                goto exit;
        }

        r += len;
    }

exit:
    writeRelocation(0xf);
    flushRelocations();
}

static void writeZPRelocations()
{
    uint8_t* r = cpm_ram;
    uint16_t pc = START_ADDRESS;
    uint16_t lastRelocation = 0;
    resetRelocationWriter();

    for (;;)
    {
        uint8_t type = *r & 0xe0;
        uint8_t len = *r & 0x1f;

        switch (type)
        {
            case RECORD_BYTES:
                pc += len - offsetof(ByteRecord, bytes);
                break;

            case RECORD_EXPR:
            {
                ExpressionRecord* s = (ExpressionRecord*)r;
                uint8_t length = s->length;
                if (s->variable && (s->variable->type == SYMBOL_ZP))
                {
                    uint16_t address;
                    if ((s->opcode == 0x00) || (s->opcode == 0xff))
                        address = pc;
                    else
                        address = pc + 1;

                    if (s->postprocessing != PP_MSB)
                    {
                        writeRelocationFor(address - lastRelocation);
                        lastRelocation = address;
                    }
                }
                pc += length;
                break;
            }

            case RECORD_EOF:
                goto exit;
        }

        r += len;
    }

exit:
    writeRelocation(0xf);
    flushRelocations();
}

/* --- Main program ------------------------------------------------------ */

int main()
{
    ramtop = (uint8_t*)(cpm_bios_gettpa() & 0xff00);
    cpm_printstring("ASM; ");
    printi(ramtop - cpm_ram);
    printnl(" bytes free");
    memset(cpm_ram, 0, ramtop - cpm_ram);

    destFcb = cpm_fcb2;

    /* Open input file */

    srcFcb.ex = 0;
    srcFcb.cr = 0;
    if (cpm_open_file(&srcFcb))
    {
        fatal("cannot open source file");
    }
    consumeByte();
    consumeToken();

    /* Open output file */

    destFcb.ex = 0;
    destFcb.cr = 0;
    cpm_delete_file(&destFcb);
    destFcb.ex = 0;
    destFcb.cr = 0;
    if (cpm_make_file(&destFcb))
    {
        cr();
        fatal("cannot create destination file");
    }

    /* Parse file into memory. */

    printnl("Parsing...");
    lineNumber++;
    parse();
    printi(top - cpm_ram);
    printnl(" bytes memory used");

    /* Code placement */

    cpm_printstring("Analysing...");
    uint8_t i = 0;
    while (placeCode(i))
    {
        i++;
        cpm_conout('.');
    }
    cr();
    printi(zpUsage);
    printnl(" bytes zero page used");
    printi(textUsage);
    printnl(" bytes TPA used");

    /* Code emission */

    printnl("Writing...");
    writeHeader();
    writeCode();
    writeZPRelocations();
    writeTextRelocations();

    /* Flush and close the output file */

    flushOutputBuffer();
    cpm_close_file(&destFcb);
    printnl("Done.");
    cpm_warmboot();
}
