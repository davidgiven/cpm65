#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <cpm.h>
#include <ctype.h>
#include "lib/printi.h"

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
static uint8_t tokenLength;
static uint16_t tokenValue;
static uint16_t tokenVariable;

static uint16_t lastSymbol = 0;

static uint8_t* top;

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
    RECORD_ALU = 2 << 5,
	RECORD_SYMBOL = 3 << 5,
};

#define ILLEGAL 0xff

#define PACKED __attribute__((packed))

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
    uint8_t opcode;
    uint16_t variable;
    uint16_t offset;
} ExpressionRecord;

typedef struct PACKED
{
	Record record;
	uint8_t flags;
	uint16_t variable;
	uint16_t offset;
	uint16_t next;
	char name[];
} SymbolRecord;

typedef struct PACKED
{
    char name[3];
    uint8_t opcode;
} Instruction;

/* --- I/O --------------------------------------------------------------- */

static void cr(void)
{
    cpm_printstring("\n\r");
}

static void fatal(const char* msg)
{
    cpm_printstring("Error: ");
    cpm_printstring(msg);
    cr();
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
}

static char readToken()
{
    if (tokenLookahead)
    {
        char c = tokenLookahead;
        tokenLookahead = 0;
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

/* --- Symbol table management ------------------------------------------- */

SymbolRecord* lookupSymbol()
{
	uint16_t s = lastSymbol;
	while (s)
	{
		SymbolRecord* r = (SymbolRecord*)(s + cpm_ram);
		uint8_t len = (r->record.descr & 0x1f) - offsetof(SymbolRecord, name);
		if ((len == tokenLength) && (memcmp(parseBuffer, r->name, len) == 0))
			return r;

		s = r->next;
	}

	return NULL;
}

SymbolRecord* addSymbol()
{
	if (lookupSymbol())
		fatal("symbol exists");
	
	uint8_t len = tokenLength + offsetof(SymbolRecord, name);
	if (len > 0x1f)
		fatal("symbol too long");

	SymbolRecord* r = addRecord(RECORD_SYMBOL | len);
	memcpy(r->name, parseBuffer, tokenLength);
	r->next = lastSymbol;
	lastSymbol = (uint8_t*)r - cpm_ram;
	return r;
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

static void expectId()
{
    char c = readToken();
    if (c != TOKEN_ID)
        fatal("expected ID");
}

static void expectNumber()
{
    char c = readToken();
    if (c != TOKEN_NUMBER)
        fatal("expected value");
}

static void expectComma()
{
    char c = readToken();
    if (c != ',')
        fatal("expected value");
}

static void expectCloseParen()
{
    char c = readToken();
    if (c != ')')
        fatal("expected close parenthesis");
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

static uint8_t parseAluArgument()
{
    char c = readToken();
    tokenVariable = 0;
    switch (c)
    {
        case '#':
            expectNumber();
            return 2 << 2;

        case '(':
            expectNumber();
            c = peekToken();
            if (c == ')')
            {
                readToken();
                expectComma();
                c = expectXorY();
                if (c != 'Y')
                    fatal("bad addressing mode");

                return 4 << 2;
            }
            else
            {
                expectComma();
                c = expectXorY();
                if (c != 'X')
                    fatal("bad addressing mode");
                expectCloseParen();

                return 0 << 2;
            }

        case TOKEN_NUMBER:
            c = peekToken();
            if (c == ',')
            {
                readToken();
                c = expectXorY();
                if (c == 'X')
                {
                    if (tokenValue < 0x100)
                        return 5 << 2;
                    else
                        return 7 << 2;
                }
                /* Must be Y */
                return 6 << 2;
            }
            else if (tokenValue < 0x100)
                return 1 << 2;
            else
                return 3 << 2;

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
                    uint8_t op = findInstruction(simpleInsns);
                    if (op != ILLEGAL)
                    {
                        emitByte(op);
                        break;
                    }

                    op = findInstruction(aluInsns);
                    if (op != ILLEGAL)
                    {
                        uint8_t b = parseAluArgument();
                        op |= b;

                        if (tokenVariable)
                        {
                            ExpressionRecord* r = addRecord(
                                sizeof(ExpressionRecord) | RECORD_ALU);
                            r->opcode = op;
                            r->variable = tokenVariable;
                            r->offset = tokenValue;
                        }
                        else
                        {
                            emitByte(op);
                            emitByte(tokenValue & 0xff);
                            switch (b)
                            {
                                case 3 << 2:
                                case 6 << 2:
                                case 7 << 2:
                                    emitByte(tokenValue >> 8);
                            }
                        }
                        break;
                    }
                }

				/* Not an instruction. Must be a symbol definition. */

				SymbolRecord* r = addSymbol();
				token = readToken();
				if (token == ':')
				{
				}
				else if (token == '=')
				{
					expectNumber();
					r->variable = tokenVariable;
					r->offset = tokenValue;
				}
				break;

            default:
                fatal("unexpected token");
        }

        token = readToken();
		if (token == 26)
			break;
        if (token != ';')
		{
			printi(token); cr();
            fatal("unexpected garbage at end of line");
		}
    }

exit:;
    addRecord(1 | RECORD_EOF);
}

/* --- Main program ------------------------------------------------------ */

int main()
{
    ramtop = (uint8_t*)(cpm_bios_gettpa() & 0xff00);
    cpm_printstring("ASM; ");
    printi(ramtop - cpm_ram);
    cpm_printstring(" bytes free\r\n");
    memset(cpm_ram, 0, ramtop - cpm_ram);

    destFcb = cpm_fcb2;

    /* Open input file */

    srcFcb.ex = 0;
    srcFcb.cr = 0;
    if (cpm_open_file(&srcFcb))
    {
        cr();
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

    parse();
    printi(top - cpm_ram);
    cpm_printstring(" bytes of tokens\r\n");

    {
        uint8_t* p = cpm_ram;
        while (p != top)
            writeByte(*p++);
    }

    /* Flush and close the output file */

    flushOutputBuffer();
    cpm_close_file(&destFcb);
}
