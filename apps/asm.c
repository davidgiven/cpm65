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

typedef struct PACKED
{
    Record record;
    uint8_t opcode;
    struct SymbolRecord* variable;
    uint16_t offset;
    uint8_t length;
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
} Instruction;

#define lengthof(a) (sizeof(a) / sizeof(*a))

#define srcFcb cpm_fcb
#define inputBuffer ((char*)cpm_default_dma)
static char inputLookahead = 0;
static uint8_t inputBufferPos = 128;
static FCB destFcb;
static uint8_t outputBuffer[128];
static uint8_t outputBufferPos;
static uint8_t* ramtop;
#define parseBuffer ((char*)outputBuffer)

static char tokenLookahead = 0;
static uint16_t tokenLookaheadValue;
static SymbolRecord* tokenLookaheadVariable;
static uint8_t tokenLength;
static uint16_t tokenValue;
static SymbolRecord* tokenVariable;
static SymbolRecord* lastSymbol;

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

enum
{
    B_XPTR = 0 << 2,
    B_ZP = 1 << 2,
    B_IMM = 2 << 2,
    B_ABS = 3 << 2,
    B_YPTR = 4 << 2,
    B_XINDEXZP = 5 << 2,
    B_YINDEX = 6 << 2,
    B_XINDEX = 7 << 2,

    B_IMPLICIT = 8 << 2, /* not actually a valid 6502 b-value */
    B_RELATIVE = 9 << 2, /* likewise */
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
    printnl(msg);
    cpm_warmboot();
}

static void pushByte(char c)
{
    inputLookahead = c;
}

static char readByte()
{
    if (inputLookahead)
    {
        uint8_t c = inputLookahead;
        inputLookahead = 0;
        return c;
    }

    if (inputBufferPos == 128)
    {
        cpm_set_dma(inputBuffer);
        int i = cpm_read_sequential(&srcFcb);
        if (i != 0)
            return 26;
        inputBufferPos = 0;
    }

    return inputBuffer[inputBufferPos++];
}

static char peekByte()
{
    char r = readByte();
    pushByte(r);
    return r;
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

static void pushToken(char c)
{
    tokenLookahead = c;
	tokenLookaheadValue = tokenValue;
	tokenLookaheadVariable = tokenVariable;
}

static char readToken()
{
    if (tokenLookahead)
    {
        char c = tokenLookahead;
        tokenLookahead = 0;
		tokenValue = tokenLookaheadValue;
		tokenVariable = tokenLookaheadVariable;
        return c;
    }

    tokenLength = 0;
    bool alpha = false;
    bool number = false;

    uint8_t c;
    do
    {
        c = readByte();
        if (c == '\\')
        {
            do
            {
                c = readByte();
            } while ((c != '\n') && (c != 26));
        }
    } while ((c == 32) || (c == 9) || (c == '\r'));

    if (c == '\n')
        c = ';';

    parseBuffer[tokenLength++] = c;
    switch (c)
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
            return c;
    }

    if (isalpha(c) || (c == '$'))
    {
        for (;;)
        {
            c = readByte();
            if (!isdigit(c) && !isalpha(c))
            {
                pushByte(c);
                break;
            }

            parseBuffer[tokenLength++] = c;
        }

        parseBuffer[tokenLength] = 0;
        return TOKEN_ID;
    }

    if (isdigit(c))
    {
        tokenValue = 0;
        uint8_t base = 10;

        if (c == '0')
        {
            c = readByte();
            if (c == 'x')
            {
                base = 16;
                c = readByte();
            }
        }

        for (;;)
        {
            if (!ishex(c))
            {
                pushByte(c);
                break;
            }

            tokenValue *= base;
            if (c >= 'a')
                c = (c - 'a') + 10;
            else if (c >= 'A')
                c = (c - 'A') + 10;
            else
                c -= '0';
            tokenValue += c;

            c = readByte();
        }

        return TOKEN_NUMBER;
    }

    if (c == '"')
    {
        tokenLength = 0;
        for (;;)
        {
            c = readByte();
            if (c == '"')
                break;
            if (c == '\n')
                fatal("unterminated string constant");
            if (c == '\\')
            {
                c = readByte();
                if (c == 'n')
                    c = 10;
                else if (c == 'r')
                    c = 13;
                else if (c == 't')
                    c = 9;
                else
                    fatal("bad escape");
            }

            parseBuffer[tokenLength++] = c;
        }

        return TOKEN_STRING;
    }

    cpm_printstring("Bad token: ");
    printi(c);
    cr();
    fatal("bad parse");
}

static char peekToken()
{
    char c = readToken();
    pushToken(c);
    return c;
}

/* --- Instruction data -------------------------------------------------- */

static uint8_t getB(uint8_t opcode)
{
    if ((opcode & 0b00000011) == 0b00000001) /* c=1 */
    {
        /* Normal ALU block */

        return opcode & 0b00011100;
    }
    else if ((opcode & 0b00000011) == 0b00000010) /* c=0 */
    {
        /* Shift instructions with ALU-compatible b-values? */

        if (opcode & 0b00000100)
            return opcode & 0b00011100;

        /* ldx # is special */

        if (opcode == 0xa2)
            return B_IMM;

        return B_IMPLICIT;
    }
    else /* c=0 */
    {
        /* Misc instructions with ALU-compatible b-values? */

        if (opcode & 0b00000100)
            return opcode & 0b00011100;

        /* Relative branches? */

        if ((opcode & 0b00011100) == 0b00010000)
            return B_RELATIVE;

        /* JSR is special */

        if (opcode == 0x20)
            return B_ABS;

        /* LDY/CPX/CPY are special */

        if ((opcode & 0b10011100) == 0b10000000)
            return B_IMM;

        return B_IMPLICIT;
    }
}

static uint8_t getBProps(uint8_t b)
{
    static const uint8_t flags[10] = {
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP | BPROP_PTR,  // B_XPTR
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP,              // B_ZP
        (2 << BPROP_SIZE_SHIFT) | BPROP_IMM,             // B_IMM
        (3 << BPROP_SIZE_SHIFT) | BPROP_ABS | BPROP_SHR, // B_ABS
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP | BPROP_PTR,  // B_YPTR
        (2 << BPROP_SIZE_SHIFT) | BPROP_ZP,              // B_XINDEXZP
        (3 << BPROP_SIZE_SHIFT) | BPROP_ABS,             // B_YINDEX
        (3 << BPROP_SIZE_SHIFT) | BPROP_ABS | BPROP_SHR, // B_XINDEX
        (1 << BPROP_SIZE_SHIFT),                         // B_IMPLICIT
        (2 << BPROP_SIZE_SHIFT) | BPROP_RELATIVE,        // B_RELATIVE
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

static void addExpressionRecord(uint8_t op, uint8_t type)
{
    if (tokenVariable)
    {
        ExpressionRecord* r = addRecord(sizeof(ExpressionRecord) | type);
        r->opcode = op;
        r->variable = tokenVariable;
        r->offset = tokenValue;
        r->length = 0xff;
    }
    else
    {
        emitByte(op);
        emitByte(tokenValue & 0xff);
        if (getInsnProps(op) & BPROP_ABS)
            emitByte(tokenValue >> 8);
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

static const Instruction simpleInsns[] = {
    {"BRK", 0x00},
    {"PHP", 0x08},
    {"CLC", 0x18},
    {"PLP", 0x28},
    {"SEC", 0x38},
    {"RTI", 0x40},
    {"PHA", 0x48},
    {"CLI", 0x58},
    {"RTS", 0x60},
    {"PLA", 0x68},
    {"SEI", 0x78},
    {"DEY", 0x88},
    {"TYA", 0x98},
    {"TAY", 0xa8},
    {"CLV", 0xb8},
    {"INY", 0xc8},
    {"CLD", 0xd8},
    {"INX", 0xe8},
    {"SED", 0xf8},
    {"TXS", 0x9a},
    {"TSX", 0xba},
    {}
};

static const Instruction aluInsns[] = {
    {"ORA", 0x01},
    {"AND", 0x21},
    {"EOR", 0x41},
    {"ADC", 0x61},
    {"STA", 0x81},
    {"LDA", 0xa1},
    {"CMP", 0xc1},
    {"SBC", 0xe1},
    {}
};

static const Instruction braInsns[] = {
    {"BPL", 0x10},
    {"BMI", 0x30},
    {"BVC", 0x50},
    {"BVS", 0x70},
    {"BCC", 0x90},
    {"BCS", 0xb0},
    {"BNE", 0xd0},
    {"BEQ", 0xf0},
    {}
};

static uint8_t findInstruction(const Instruction* insn)
{
    char opcode[3];

    for (int i = 0; i < 3; i++)
        opcode[i] = toupper(parseBuffer[i]);

    while (insn->name[0])
    {
        if ((opcode[0] == insn->name[0]) && (opcode[1] == insn->name[1]) &&
            (opcode[2] == insn->name[2]))
        {
            return insn->opcode;
        }

        insn++;
    }

    return ILLEGAL;
}

static void syntaxError()
{
    fatal("syntax error");
}

static void expect(char token)
{
    char c = readToken();
    if (c != token)
        syntaxError();
}

static char expectXorY()
{
    char c = readToken();
    if ((c == TOKEN_ID) && (tokenLength == 1))
    {
        c = toupper(parseBuffer[0]);
        if ((c == 'X') || (c == 'Y'))
            return c;
    }
    fatal("expected X or Y");
}

static void parseExpression()
{
    tokenValue = 0;
    tokenVariable = NULL;
    char c = readToken();
    switch (c)
    {
        case TOKEN_NUMBER:
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

            c = peekToken();
            if ((c == '+') || (c == '-'))
            {
                readToken();
                expect(TOKEN_NUMBER);
                if (c == '+')
                    offset += tokenValue;
                else
                    offset -= tokenValue;
            }
            tokenValue = offset;

            return;
        }

        default:
            syntaxError();
    }
}

static uint8_t parseAluArgument()
{
    char c = readToken();
    tokenVariable = NULL;
    switch (c)
    {
        case '#':
            parseExpression();
            return B_IMM;

        case '(':
            parseExpression();
            c = peekToken();
            if (c == ')')
            {
                readToken();
                expect(',');
                c = expectXorY();
                if (c != 'Y')
                    fatal("bad addressing mode");

                return B_YPTR;
            }
            else
            {
                expect(',');
                c = expectXorY();
                if (c != 'X')
                    fatal("bad addressing mode");
                expect(')');

                return B_XPTR;
            }

        case TOKEN_ID:
        case TOKEN_NUMBER:
            pushToken(c);
            parseExpression();
            c = peekToken();
            if (c == ',')
            {
                readToken();
                c = expectXorY();
                if (c == 'X')
                {
                    if (!tokenVariable && (tokenValue < 0x100))
                        return B_XINDEXZP;
                    else
                        return B_XINDEX;
                }
                /* Must be Y */
                return B_YINDEX;
            }
            else if (!tokenVariable && (tokenValue < 0x100))
                return B_ZP;
            else
                return B_ABS;

        default:
            fatal("bad addressing mode");
    }
}

static void parse()
{
    top = cpm_ram;

    for (;;)
    {
        char token = readToken();
        switch (token)
        {
            case TOKEN_EOF:
                goto exit;

            case ';':
                break;

            case TOKEN_ID:
                /* Process instructions. */

                if (tokenLength == 3)
                {
                    /* Simple instructions */

                    uint8_t op = findInstruction(simpleInsns);
                    if (op != ILLEGAL)
                    {
                        emitByte(op);
                        break;
                    }

                    /* 'Normal' ALU instructions */

                    op = findInstruction(aluInsns);
                    if (op != ILLEGAL)
                    {
                        uint8_t b = parseAluArgument();
                        op |= b;

                        addExpressionRecord(op, RECORD_EXPR);
                        break;
                    }

                    /* Conditional branch instructions */

                    op = findInstruction(braInsns);
                    if (op != ILLEGAL)
                    {
                        parseExpression();

                        addExpressionRecord(op, RECORD_EXPR);
                        break;
                    }
                }

                /* Not an instruction. Must be a symbol definition. */

                SymbolRecord* r = addOrFindSymbol();
                token = readToken();
                if (token == ':')
                {
                    if ((r->type != SYMBOL_UNINITIALISED) &&
                        (r->type != SYMBOL_REFERENCE))
                        symbolExists();
                    r->type = SYMBOL_TEXT;

                    LabelDefinitionRecord* r2 = addRecord(
                        sizeof(LabelDefinitionRecord) | RECORD_LABELDEF);
                    r2->variable = r;
                    break;
                }
                else if (token == '=')
                {
                    if (r->type != SYMBOL_UNINITIALISED)
                        symbolExists();

                    parseExpression();
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

        token = readToken();
        if (token == 26)
            break;
        if (token != ';')
        {
            printi(token);
            cr();
            fatal("unexpected garbage at end of line");
        }
    }

exit:;
    addRecord(1 | RECORD_EOF);
}

/* --- Code placement ---------------------------------------------------- */

static bool placeCode(uint8_t pass)
{
    bool changed = false;
    uint8_t* r = cpm_ram;
    uint16_t pc = 0;
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

                /* Shrink anything which is pointing into zero page. */

                if (s->variable && (s->variable->type == SYMBOL_ZP) &&
                    (bprops & BPROP_SHR))
                {
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
    return changed;
}

/* --- Code emission ----------------------------------------------------- */

static void writeCode()
{
    uint8_t* r = cpm_ram;
	uint8_t pc = 0;
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
                    writeByte(s->opcode);

                    uint16_t address = s->offset;
                    if (s->variable)
                        address += s->variable->offset;

                    writeByte(address & 0xff);
                    if (s->length == 3)
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
    uint16_t pc = 0;
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
                if (getInsnProps(s->opcode) & BPROP_ABS)
                {
                    if (s->variable)
                    {
                        switch (s->variable->type)
                        {
                            case SYMBOL_TEXT:
                            {
                                uint16_t address = pc + 2;
                                writeRelocationFor(address - lastRelocation);
                                lastRelocation = address;
                                break;
                            }
                        }
                    }
                }
                pc += getInsnLength(s->opcode);
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
    uint16_t pc = 0;
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
                if (s->variable)
                {
                    switch (s->variable->type)
                    {
                        case SYMBOL_ZP:
                        {
                            uint16_t address = pc + 1;
                            writeRelocationFor(address - lastRelocation);
                            lastRelocation = address;
                            break;
                        }
                    }
                }
                pc += getInsnLength(s->opcode);
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

    printnl("Parsing");
    parse();
    printi(top - cpm_ram);
    printnl(" bytes memory used");

    /* Code placement */

    printnl("Analysing");
    uint8_t i = 0;
    while (placeCode(i))
        i++;

    /* Code emission */

    printnl("Writing");
    writeCode();
    writeTextRelocations();
    writeZPRelocations();

    /* Flush and close the output file */

    flushOutputBuffer();
    cpm_close_file(&destFcb);
}
