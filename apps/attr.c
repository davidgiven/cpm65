#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <cpm.h>
#include <ctype.h>
#include "lib/printi.h"

static const FCB wildcard_fcb = {
    /* dr */ 0,
    /* f  */ "???????????"};

char* cmdptr = cpm_cmdline;

static const char* getword()
{
    const char* word = cmdptr;
    if (!*cmdptr)
        return NULL;

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

    return word;
}

static void print_filename(uint8_t dr, DIRE* de)
{
    cpm_conout(('A' - 1) + dr);
    cpm_conout(':');

    for (uint8_t i = 0; i < 11; i++)
    {
        uint8_t b = de->f[i] & 0x7f;
        if (b != ' ')
        {
            if (i == 8)
                cpm_conout('.');
            cpm_conout(b);
        }
    }
}

int main()
{
    static uint8_t breset[3] = {0};
    static uint8_t bset[3] = {0};
    bool modify = false;

    getword(); /* skip the filename */
    const char* attrspec = getword();

    if (attrspec)
        for (;;)
        {
            char w = *attrspec++;
            uint8_t* array = bset;

            if (w == '!')
            {
                w = *attrspec++;
                array = breset;
            }

            if (!w)
                break;

            modify = true;
            if (w == 'R')
                array[0] = 0x80;
            else if (w == 'S')
                array[1] = 0x80;
            else if (w == 'A')
                array[2] = 0x80;
            else
            {
                cpm_printstring("Bad attribute specifier: ");
                cpm_conout(w);
                cpm_printstring("\r\n");
                return 1;
            }
        }

    FCB* fcb = &cpm_fcb;
    if (fcb->f[0] == ' ')
        fcb = (FCB*)&wildcard_fcb;

    uint8_t dr = fcb->dr;
    if (!dr)
        dr = cpm_get_current_drive() + 1;

    cpm_set_dma(cpm_default_dma);
    uint8_t r = cpm_findfirst(fcb);
    while (r != 0xff)
    {
        DIRE* de = (DIRE*)cpm_default_dma + r;
        if (de->rc == 0x80)
            continue;

        if (modify)
        {
            for (int i = 0; i < 3; i++)
            {
                de->f[8 + i] &= ~breset[i];
                de->f[8 + i] |= bset[i];
            }

            de->us = dr; /* Convert to an FCB */
            cpm_set_file_attributes((FCB*)de);
        }

        cpm_conout((de->f[8] & 0x80) ? 'R' : '-');
        cpm_conout((de->f[9] & 0x80) ? 'S' : '-');
        cpm_conout((de->f[10] & 0x80) ? 'A' : '-');
        cpm_conout(' ');

        print_filename(dr, de);
        cpm_printstring("\r\n");
        r = cpm_findnext(fcb);
    }
    return 0;
}
