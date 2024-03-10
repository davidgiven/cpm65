#include <stdlib.h>
#include <string.h>
#include <cpm.h>
#include "lib/printi.h"

#define infile cpm_fcb
static FCB outfile;

static int lineno = 1;

#define MAX_PROCS 200
static uint8_t proccount = 0;
static uint16_t procedures[MAX_PROCS];

static uint8_t outbufptr = 0;

static void malformed(const char* s)
{
    cpm_printstring("Malformed input line: ");
    cpm_printstring(s);
    cpm_printstring(" at line ");
    printi(lineno);
    cpm_printstring("\r\n");
}

static uint8_t digit(uint8_t c)
{
    if ((c >= '0') && (c <= '9'))
        return c - '0';
    if ((c >= 'A') && (c <= 'F'))
        return c - 'A' + 10;
    if ((c >= 'a') && (c <= 'f'))
        return c - 'a' + 10;
    return 0;
}

static uint8_t gethex2(const uint8_t* ptr)
{
    return (digit(ptr[0]) << 4) | digit(ptr[1]);
}

static uint16_t gethex4(const uint8_t* ptr)
{
    return (gethex2(ptr) << 8) | gethex2(ptr + 2);
}

static uint8_t checksum(const uint8_t* start, const uint8_t* end)
{
    uint16_t c = 0;
    while (start != end)
    {
        c += gethex2(start);
        start += 2;
    }
    return (16383 - c) % 256;
}

static void flushoutput()
{
    cpm_write_sequential(&outfile);
    outbufptr = 0;
    memset(cpm_default_dma, 0, 128);
}

static void writebyte(uint8_t b)
{
    cpm_default_dma[outbufptr++] = b;
    if (outbufptr == 0x80)
        flushoutput();
}

static void writeword(uint16_t w)
{
    writebyte(w & 0xff);
    writebyte(w >> 8);
}

void main()
{
    memcpy(&outfile, &cpm_fcb2, 16);

    if ((infile.f[0] == ' ') || (outfile.f[0] == ' '))
    {
        cpm_printstring("Syntax: ploader <in.obp> <out.obb>\r\n");
        return;
    }

    cpm_printstring("Opening input file...\r\n");
    infile.cr = 0;
    if (cpm_open_file(&infile) != 0)
    {
        cpm_printstring("Failed.\r\n");
        return;
    }

    cpm_printstring("Opening output file...\r\n");
    cpm_delete_file(&outfile);
    outfile.cr = 0;
    if (cpm_make_file(&outfile) != 0)
    {
        cpm_printstring("Failed.\r\n");
        return;
    }

    cpm_printstring("Reading OBP...\r\n");

    uint8_t p = 0x80;
    uint8_t lineptr = 0;
    static uint16_t outoffset = 0;
    static uint16_t procoffset = 0;
    static uint8_t linebuf[80];
    cpm_set_dma(cpm_default_dma);
    for (;;)
    {
        if (p == 0x80)
        {
            uint8_t r = cpm_read_sequential(&infile);
            if (r)
                break;
            p = 0;
        }

        uint8_t c = cpm_default_dma[p++];
        if (c == '\r')
            continue;
        linebuf[lineptr++] = c;
        if (lineptr == sizeof(linebuf))
        {
            malformed("too long");
            return;
        }

        if (c == '\n')
        {
            if (linebuf[0] == 'P')
            {
                uint8_t rchecksum = gethex2(linebuf + lineptr - 3);
                switch (linebuf[1])
                {
                    case '1':
                    {
                        uint8_t count = gethex2(linebuf + 2);
                        for (uint8_t* p = linebuf + 4;
                             p != linebuf + lineptr - 3;
                             p += 2)
                            cpm_ram[outoffset++] = gethex2(p);

                        if (checksum(linebuf + 2, linebuf + lineptr - 3) !=
                            rchecksum)
                        {
                            malformed("checksum error in P1 record");
                            return;
                        }
                        break;
                    }

                    case '2':
                    {
                        uint16_t address = gethex4(linebuf + 2);
                        uint16_t value = gethex4(linebuf + 6);

                        cpm_ram[address + 0] = value >> 8;
                        cpm_ram[address + 1] = value & 0xff;

                        if (checksum(linebuf + 2, linebuf + lineptr - 3) !=
                            rchecksum)
                        {
                            malformed("checksum error in P2 record");
                            return;
                        }
                        break;
                    }

                    case '4':
                    {
                        uint8_t procnum = gethex2(linebuf + 2);
                        if (procnum >= MAX_PROCS)
                        {
                            malformed("too many procedures");
                            return;
                        }
                        if (procnum >= proccount)
                            proccount = procnum + 1;
                        procoffset = outoffset;
                        procedures[procnum] = outoffset;

                        uint16_t checksum = procnum;
                        for (uint8_t* p = linebuf + 4;
                             p != linebuf + lineptr - 3;
                             p++)
                            checksum += *p;
                        checksum = (16383 - checksum) % 256;

                        if (checksum != rchecksum)
                        {
                            malformed("checksum error in P4 record");
                            return;
                        }
                        break;
                    }

                    case '9':
                        goto finished_read;

                    default:
                        malformed("invalid P-record");
                        return;
                }
            }
            lineptr = 0;
            lineno++;
        }
    }
finished_read:;
    cpm_printstring("Seen ");
    printi(proccount);
    cpm_printstring(" procedures\r\n");
    cpm_printstring("Writing output file...\r\n");

    memset(cpm_default_dma, 0, 128);
    writeword(proccount*2 + 2); /* offset to mcode start */
    for (int i=0; i<proccount; i++)
        writeword(procedures[i] + proccount*2);

    for (const uint8_t* p = cpm_ram; p < (cpm_ram + outoffset); p++)
        writebyte(*p);

    cpm_printstring("Closing output file...\r\n");
    flushoutput();
    cpm_close_file(&outfile);
    cpm_printstring("Success.\r\n");
}
