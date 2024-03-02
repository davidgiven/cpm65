#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cpm.h>
#include "neo6502.h"

static uint8_t getattrs(const char* filename)
{
    int filenamelen = strlen(filename);
    char filenamep[filenamelen + 1];
    filenamep[0] = filenamelen;
    memcpy(filenamep + 1, filename, filenamelen);

    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_STAT;
    *(volatile void**)(CP_PARAM + 0) = filenamep;
    CP_GROUP = GROUP_FILE;

    while (CP_GROUP)
        ;

    if (CP_ERRNO)
    {
        cpm_printstring("Failed.\r\n");
        cpm_warmboot();
    }

    return CP_PARAM[4];
}

static void setattrs(const char* filename, uint8_t attrbits)
{
    int filenamelen = strlen(filename);
    char filenamep[filenamelen + 1];
    filenamep[0] = filenamelen;
    memcpy(filenamep + 1, filename, filenamelen);

    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_SETATTRS;
    *(volatile void**)(CP_PARAM + 0) = filenamep;
    *(volatile uint8_t*)(CP_PARAM + 2) = attrbits;
    CP_GROUP = GROUP_FILE;

    while (CP_GROUP)
        ;

    if (CP_ERRNO)
    {
        cpm_printstring("Failed.\r\n");
        cpm_warmboot();
    }
}

int main(int argc, const char* argv[])
{
    cpm_cmdline[cpm_cmdlinelen] = 0;

    const char* filename = getword();

    if (!filename)
        cpm_printstring("Syntax: nattr <filename> [<attrbits>...]\r\n");
    else
    {
        cpm_printstring("Setting attributes of '");
        cpm_printstring(filename);
        cpm_printstring("':\r\n");

        uint8_t attrs = getattrs(filename);
        cpm_printstring("Old:  ");
        printattrs(attrs);
        cpm_printstring("\r\n");

        for (;;)
        {
            const char* param = getword();
            if (!param)
                break;

            if (strcmp(param, "R") == 0)
                attrs |= FIOATTR_READONLY;
            else if (strcmp(param, "!R") == 0)
                attrs &= ~FIOATTR_READONLY;
            else if (strcmp(param, "S") == 0)
                attrs |= FIOATTR_SYSTEM;
            else if (strcmp(param, "!S") == 0)
                attrs &= ~FIOATTR_SYSTEM;
            else if (strcmp(param, "A") == 0)
                attrs |= FIOATTR_ARCHIVE;
            else if (strcmp(param, "!A") == 0)
                attrs &= ~FIOATTR_ARCHIVE;
            else if (strcmp(param, "H") == 0)
                attrs |= FIOATTR_HIDDEN;
            else if (strcmp(param, "!H") == 0)
                attrs &= ~FIOATTR_HIDDEN;
            else
            {
                cpm_printstring("Ignoring unknown parameter '");
                cpm_printstring(param);
                cpm_printstring("'\r\n");
            }
        }

        cpm_printstring("Want: ");
        printattrs(attrs);
        cpm_printstring("\r\n");

        setattrs(filename, attrs);

        cpm_printstring("New:  ");
        printattrs(getattrs(filename));
        cpm_printstring("\r\n");

        cpm_printstring("Suceeded.\r\n");
    }

    return 0;
}