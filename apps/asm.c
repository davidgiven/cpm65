#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <cpm.h>
#include "lib/printi.h"

#define srcFcb cpm_fcb
#define inputBuffer ((uint8_t*)cpm_default_dma)
static uint8_t inputBufferPos = 128;
static FCB destFcb;
static uint8_t outputBuffer[128];
static uint8_t outputBufferPos;
static uint8_t* ramtop;

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

static uint8_t readByte()
{
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

/* --- Main program ------------------------------------------------------ */

int main()
{
	ramtop = (uint8_t*)(cpm_bios_gettpa() & 0xff00);
	cpm_printstring("ASM; ");
	printi(ramtop - cpm_ram);
	cpm_printstring(" bytes free\n");

    destFcb = cpm_fcb2;

    srcFcb.ex = 0;
    srcFcb.cr = 0;
    if (cpm_open_file(&srcFcb))
    {
        cr();
        fatal("cannot open source file");
    }

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

    for (;;)
    {
        uint8_t c = readByte();
        writeByte(c);
        if (c == 26)
            break;
    }

    flushOutputBuffer();
    cpm_close_file(&destFcb);
}
