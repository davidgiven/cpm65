#include <stdlib.h>
#include <cpm.h>
#include "neo6502.h"

char* cmdptr = cpm_cmdline;

const char* getword()
{
    const char* word = cmdptr;
    if (!*cmdptr)
        return NULL;

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

    return word;
}

void printattrs(uint8_t attrbits)
{
    cpm_printstring((attrbits & FIOATTR_DIR) ? "D " : "!D ");
    cpm_printstring((attrbits & FIOATTR_READONLY) ? "R " : "!R ");
    cpm_printstring((attrbits & FIOATTR_SYSTEM) ? "S " : "!S ");
    cpm_printstring((attrbits & FIOATTR_ARCHIVE) ? "A " : "!A ");
    cpm_printstring((attrbits & FIOATTR_HIDDEN) ? "H " : "!H ");
}

void print_d32(uint32_t value)
{
    if (value == 0)
    {
        cpm_conout('0');
        return;
    }

    char buffer[16];
    char* p = buffer;
    ldiv_t d;
    d.quot = value;
    while (d.quot != 0)
    {
        d = ldiv(d.quot, 10);
        *p++ = d.rem + '0';
    }

    while (p != buffer)
        cpm_conout(*--p);
}
