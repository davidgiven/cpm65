/* copy © 2022 David Given
 * This program is distributable under the terms of the 2-clause BSD license.
 * See COPYING.cpmish in the distribution root directory for more information.
 * 
 * A buffered file copier, supporting wildcards when copying to another drive.
 * User areas are not currently supported.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <cpm.h>

static FCB wildcard_fcb;
static FCB src_fcb;
static FCB dest_fcb;
static uint16_t buffer_size;
static char* cmdptr = cpm_cmdline;
static bool s_flag = false;

static const char* getword()
{
	const char* word = cmdptr;
	if (*cmdptr)
	{
		while (*cmdptr == ' ')
			cmdptr++;

		for (;;)
		{
			char c = *cmdptr;
			if (!c)
				break;
			if (c == ' ')
			{
				*cmdptr++ = '\0';
				break;
			}

			cmdptr++;
		}
	}

	return word;
}

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

static bool has_wildcard(const FCB* fcb)
{
	for (int i=0; i<12; i++)
		if (fcb->f[i] == '?')
			return true;
	return false;
}

static void print_fcb(FCB* fcb)
{
	if (fcb->dr)
	{
		cpm_conout('A' + fcb->dr-1);
		cpm_conout(':');
	}

	for (int i=0; i<8; i++)
	{
		uint8_t c = fcb->f[i] & 0x7f;
		if (c == ' ')
			break;
		cpm_conout(c);
	}

	if (fcb->f[8] != ' ')
	{
		cpm_conout('.');
		for (int i=8; i<11; i++)
		{
			uint8_t c = fcb->f[i] & 0x7f;
			if (c == ' ')
				break;
			cpm_conout(c);
		}
	}
}

static void copy_file(void)
{
	cpm_printstring("Copying ");
	print_fcb(&src_fcb);
	cpm_printstring(" -> ");
	print_fcb(&dest_fcb);
	cpm_printstring(": ");

	src_fcb.ex = 0;
	src_fcb.cr = 0;
	if (cpm_open_file(&src_fcb) || ((src_fcb.f[9] & 0x80) && !s_flag))
	{
		cr();
		fatal("cannot open source file");
	}

	dest_fcb.ex = 0;
	dest_fcb.cr = 0;
	cpm_delete_file(&dest_fcb);
	dest_fcb.ex = 0;
	dest_fcb.cr = 0;
	if (cpm_make_file(&dest_fcb))
	{
		cr();
		fatal("cannot create destination file");
	}

	uint8_t i = false;
	do
	{
		uint16_t sr = 0;
		while (sr != buffer_size)
		{
			cpm_conout('r');
			cpm_set_dma(cpm_ram + sr*128);
			i = cpm_read_sequential(&src_fcb);
			if (i != 0)
				break;
			sr++;
		}

		uint16_t dr = 0;
		while (dr != sr)
		{
			cpm_conout('w');
			cpm_set_dma(cpm_ram + dr*128);
			cpm_write_sequential(&dest_fcb);
			dr++;
		}
	}
	while (i == 0);
	cpm_close_file(&dest_fcb);
	cr();
}

void parse_cmdline()
{
	const char *arg;

	cpm_fcb.f[0] = ' ';
	cpm_fcb2.f[0] = ' ';

	while (*(arg = getword()))
	{
		if ('/' == *arg)
		{
			if('S' == *++arg)
				++s_flag;
			else
				fatal("Invalid switch");
		}
		else if (cpm_fcb.f[0] == ' ')
		{
			cpm_set_dma(&cpm_fcb);
			cpm_parse_filename(arg);
		}
		else if (cpm_fcb2.f[0] == ' ')
		{
			cpm_set_dma(&cpm_fcb2);
			cpm_parse_filename(arg);
			break;
		}
	}
}

int main()
{
	parse_cmdline();

	if (cpm_fcb.f[0] == ' ')
		fatal("source must contain a filename");
	if (has_wildcard(&cpm_fcb2))
		fatal("destination may not contain a wildcard");
	if ((cpm_fcb2.f[0] != ' ') && has_wildcard(&cpm_fcb))
		fatal("destination can't contain a filename when using wildcards");

	uint16_t tpa = cpm_bios_gettpa();
	uint8_t* top = (uint8_t*) (tpa & 0xff00);

	if (has_wildcard(&cpm_fcb))
	{
		if (cpm_fcb.dr == cpm_fcb2.dr)
			fatal("refusing to copy files on top of themselves!");

		wildcard_fcb = cpm_fcb;
		cpm_set_dma(cpm_default_dma);
		uint8_t i = cpm_findfirst(&wildcard_fcb);
		FCB* stash = (FCB*) top;
		while (i != 0xff)
		{
			FCB* dire = (FCB*) (cpm_default_dma + i*32);
			if (!(dire->f[9] & 0x80) || s_flag)
				*--stash = *dire;

			i = cpm_findnext(&wildcard_fcb);
		}

		if (stash == (FCB*)top)
			fatal("no files match");
		buffer_size = ((uint16_t)stash - (uint16_t)cpm_ram) / 128;

		while (stash != (FCB*)top)
		{
			src_fcb = *stash;
			dest_fcb = *stash;
			dest_fcb.dr = cpm_fcb2.dr;
			for (uint8_t b=0; b < 11; b++)
				dest_fcb.f[b] &= ~0x80;
			stash++;

			copy_file();
		}
	}
	else
	{
		buffer_size = ((uint16_t)top - (uint16_t)cpm_ram) / 128;
		src_fcb = cpm_fcb;
		if (cpm_fcb2.f[0] != ' ')
			dest_fcb = cpm_fcb2;
		else
		{
			if (cpm_fcb.dr == cpm_fcb2.dr)
				fatal("refusing to copy files on top of themselves!");
			dest_fcb = src_fcb;
			dest_fcb.dr = cpm_fcb2.dr;
		}

		copy_file();
	}

	cpm_warmboot();
}

