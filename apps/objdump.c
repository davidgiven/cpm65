/* dump © 2019 David Given
 * This program is distributable under the terms of the 2-clause BSD license.
 * See COPYING.cpmish in the distribution root directory for more information.
 *
 * Does a hex dump of a relocatable object file, for debugging purposes.
 */

#include <cpm.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "../third_party/lib6502/6502data.h"

static char outbuffer[64];
static char* outptr;
static uint8_t* zprelos;
static uint8_t* tparelos;

struct insn
{
    const char* name;
    uint8_t (*cb)(uint16_t ip, const uint8_t* b);
};

static void print(const char* s)
{
    for (;;)
    {
        uint8_t b = *s++;
        if (!b)
            return;
        cpm_conout(b);
    }
}

static void crlf(void)
{
    print("\r\n");
}

static void printx(const char* s)
{
    print(s);
    crlf();
}

static void oh1(uint8_t b)
{
    if (b < 10)
        b += '0';
    else
        b += 'a' - 10;
    *outptr++ = b;
}

static void oh2(uint8_t b)
{
    oh1(b >> 4);
    oh1(b & 0x0f);
}

static void oh4(uint16_t w)
{
    oh2(w >> 8);
    oh2(w);
}

static void os(const char* src)
{
    for (;;)
    {
        char b = *src++;
        if (!b)
            break;
        *outptr++ = b;
    }
}

static void fatal(const char* s)
{
    printx(s);
    cpm_warmboot();
}

static uint8_t implied_cb(uint16_t ip, const uint8_t* b)
{
    return 1;
}

static uint8_t immediate_cb(uint16_t ip, const uint8_t* b)
{
    *outptr++ = '#';
    oh2(b[1]);
    return 2;
}

static uint8_t zp_cb(uint16_t ip, const uint8_t* b)
{
    oh2(b[1]);
    return 2;
}

static uint8_t zpx_cb(uint16_t ip, const uint8_t* b)
{
    oh2(b[1]);
    os(", x");
    return 2;
}

static uint8_t zpy_cb(uint16_t ip, const uint8_t* b)
{
    oh2(b[1]);
    os(", y");
    return 2;
}

static uint8_t abs_cb(uint16_t ip, const uint8_t* b)
{
    oh2(b[2]);
    oh2(b[1]);
    return 3;
}

static uint8_t absx_cb(uint16_t ip, const uint8_t* b)
{
    abs_cb(ip, b);
    os(", x");
    return 3;
}

static uint8_t absy_cb(uint16_t ip, const uint8_t* b)
{
    abs_cb(ip, b);
    os(", y");
    return 3;
}

static uint8_t relative_cb(uint16_t ip, const uint8_t* b)
{
    oh4(ip + 2 + (int8_t)b[1]);
    return 2;
}

static uint8_t indirect_cb(uint16_t ip, const uint8_t* b)
{
    *outptr++ = '(';
    oh2(b[2]);
    oh2(b[1]);
    *outptr++ = ')';
    return 3;
}

static uint8_t indzp_cb(uint16_t ip, const uint8_t* b)
{
    *outptr++ = '(';
    oh2(b[1]);
    *outptr++ = ')';
    return 2;
}

static uint8_t indx_cb(uint16_t ip, const uint8_t* b)
{
    *outptr++ = '(';
    oh2(b[1]);
    os(", x)");
    return 2;
}

static uint8_t indy_cb(uint16_t ip, const uint8_t* b)
{
    *outptr++ = '(';
    oh2(b[1]);
    os("), y");
    return 2;
}

static uint8_t indabsx_cb(uint16_t ip, const uint8_t* b)
{
    *outptr++ = '(';
    oh2(b[2]);
    oh2(b[1]);
    os(", x)");
    return 3;
}

static uint8_t zpr_cb(uint16_t ip, const uint8_t* b)
{
    oh2(b[1]);
    *outptr++ = ',';
    oh4(ip + 2 + (int8_t)b[2]);
    return 3;
}

#define disassemble(num, name, mode, cycles) {#name, mode##_cb},

static const struct insn insns[] = {do_insns(disassemble)};

#undef _do
#undef disassemble

static int disassemble(uint16_t ip)
{
    uint8_t* b = cpm_ram + ip;
    const struct insn* insn = &insns[*b];
    os(insn->name);
    *outptr++ = ' ';
    return insn->cb(ip, b);
}

static uint16_t getrelo(uint8_t** ptr)
{
	uint16_t delta = 0;
	for (;;)
	{
		uint8_t b = *(*ptr)++;
		delta += b;
		if (b == 0xf)
			return 0xffff;
		if (b != 0xe)
			break;
	}
	return delta;
}

int main(int argc, char* argv[])
{
    cpm_fcb.cr = 0;
    if (cpm_open_file(&cpm_fcb))
        fatal("could not open input file");

    uint8_t* ptr = cpm_ram;
    for (;;)
    {
        uint8_t i;

        cpm_set_dma(ptr);
        if (cpm_read_sequential(&cpm_fcb))
        {
            if (cpm_errno == CPME_NOBLOCK)
                break;
            fatal("read error");
        }

        ptr += 128;
    }

    outptr = outbuffer;
    os("ZP: ");
    oh2(cpm_ram[0]);
    os(" TPA: ");
    oh2(cpm_ram[1]);
    uint16_t relo = *(uint16_t*)&cpm_ram[2];

	{
		uint8_t* r = cpm_ram + relo;

		zprelos = ptr;
		for (;;)
		{
			uint8_t b = *r++;
			*ptr++ = b >> 4;
			*ptr++ = b & 0xf;
			if (((b & 0xf0) == 0xf0) || ((b & 0x0f) == 0x0f))
				break;
		}

		tparelos = ptr;
		for (;;)
		{
			uint8_t b = *r++;
			*ptr++ = b >> 4;
			*ptr++ = b & 0xf;
			if (((b & 0xf0) == 0xf0) || ((b & 0x0f) == 0x0f))
				break;
		}
	}

	os(" ZPRELO: ");
	oh4(relo);
	os(" TPARELO: ");
	oh4(tparelos - zprelos + relo);
	*outptr = 0;
	printx(outbuffer);

    uint16_t ip = 0;
	uint16_t nextzprelo = getrelo(&zprelos);
	uint16_t nexttparelo = getrelo(&tparelos);
    while (ip < relo)
    {
        outptr = outbuffer;
        memset(outbuffer, ' ', sizeof(outbuffer));

        oh4(ip);
        outptr = outbuffer + 4 + (3 * 3) + 2 + 3 + 3;
        uint8_t len = disassemble(ip);
        *outptr = '\0';

        outptr = outbuffer + 6;
        for (uint8_t i = 0; i < len; i++)
        {
            uint8_t b = cpm_ram[ip + i];

            outptr = outbuffer + 6 + i * 3;
            oh2(cpm_ram[ip + i]);

            outptr = outbuffer + 16 + i;
            if ((b < 32) || (b > 126))
                b = '.';
            *outptr = b;
        }

        printx(outbuffer);

		do
		{
			if (ip == nextzprelo)
			{
				outptr = outbuffer;
				os("  ZPRELO ");
				oh4(ip);
				*outptr = 0;
				printx(outbuffer);
				nextzprelo += getrelo(&zprelos);
			}
			if (ip == nexttparelo)
			{
				outptr = outbuffer;
				os("  TPARELO ");
				oh4(ip);
				*outptr = 0;
				printx(outbuffer);
				nexttparelo += getrelo(&tparelos);
			}
			ip++;
		} while (--len);
    }

    return 0;
}
