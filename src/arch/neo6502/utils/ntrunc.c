#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cpm.h>
#include "neo6502.h"

static const int WIDTH = 20;

static void fail()
{
    cpm_printstring("Failed.\r\n");
    cpm_warmboot();
}

static uint32_t getsize(const char* filename)
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
        fail();

    return *(volatile uint32_t*)(CP_PARAM + 0);
}

static void open(uint8_t channel, const char* filename, uint8_t mode)
{
    int filenamelen = strlen(filename);
    char filenamep[filenamelen + 1];
    filenamep[0] = filenamelen;
    memcpy(filenamep + 1, filename, filenamelen);

    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_OPEN;
    *(volatile uint8_t*)(CP_PARAM + 0) = channel;
    *(volatile void**)(CP_PARAM + 1) = filenamep;
    *(volatile uint32_t*)(CP_PARAM + 3) = mode;
    CP_GROUP = GROUP_FILE;

    while (CP_GROUP)
        ;

    if (CP_ERRNO)
        fail();
}

static void close(uint8_t channel)
{
    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_CLOSE;
    *(volatile uint8_t*)(CP_PARAM + 0) = channel;
    CP_GROUP = GROUP_FILE;

    while (CP_GROUP)
        ;

    if (CP_ERRNO)
        fail();
}

static void truncate(uint8_t channel, uint32_t size)
{
    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_SETSIZE;
    *(volatile uint8_t*)(CP_PARAM + 0) = channel;
    *(volatile uint32_t*)(CP_PARAM + 1) = size;
    CP_GROUP = GROUP_FILE;

    while (CP_GROUP)
        ;

    if (CP_ERRNO)
        fail();
}

int main(int argc, const char* argv[])
{
    cpm_cmdline[cpm_cmdlinelen] = 0;

    const char* path = getword();
    const char* sizes = getword();

    if (!path || !sizes || *cmdptr)
        cpm_printstring("Syntax: ntrunc <filename> <size>\r\n");
    else
    {
        cpm_printstring("Truncating '");
        cpm_printstring(path);
        cpm_printstring("':\r\n");

        cpm_printstring("Old size:    ");
        print_d32(getsize(path));
        cpm_printstring("\r\n");

        uint32_t size = atol(sizes);
        cpm_printstring("Wanted size: ");
        print_d32(size);
        cpm_printstring("\r\n");

        /* All file channels are used by CP/M, so this will screw up the file
         * table big time.  Do not perform any CP/M file operations after here. */
        close(0);
        open(0, path, FIOMODE_RDWR);
        truncate(0, size);
        close(0);

        cpm_printstring("New size:    ");
        print_d32(getsize(path));
        cpm_printstring("\r\n");
    }

    cpm_warmboot();
}
