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

static void opendir(const char* path)
{
    int pathlen = strlen(path);
    char pathp[pathlen + 1];
    pathp[0] = pathlen;
    memcpy(pathp + 1, path, pathlen);

    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_OPENDIR;
    *(volatile void**)(CP_PARAM + 0) = pathp;
    CP_GROUP = GROUP_FILE;

    while (CP_GROUP)
        ;
    if (CP_ERRNO)
        fail();
}

static void closedir()
{
    while (CP_GROUP)
        ;

    CP_FUNCTION = FUNC_FILE_CLOSEDIR;
    CP_GROUP = GROUP_FILE;
}

int main(int argc, const char* argv[])
{
    cpm_cmdline[cpm_cmdlinelen] = 0;

    const char* path = getword();
    if (!path)
        path = ".";

    if (*cmdptr)
        cpm_printstring("Syntax: ndir [<path>]\r\n");
    else
    {
        cpm_printstring("Directory listing of '");
        cpm_printstring(path);
        cpm_printstring("':\r\n");

        opendir(path);

        for (;;)
        {
            char buffer[255];
            buffer[0] = sizeof(buffer) - 2;

            while (CP_GROUP)
                ;

            CP_FUNCTION = FUNC_FILE_READDIR;
            *(volatile void**)(CP_PARAM + 0) = buffer;
            CP_GROUP = GROUP_FILE;

            while (CP_GROUP)
                ;
            if (CP_ERRNO)
                break;

            buffer[buffer[0] + 1] = 0;
            cpm_printstring(buffer + 1);

            for (int i = buffer[0]; i < WIDTH; i++)
                cpm_conout(' ');

            printattrs(CP_PARAM[6]);

            uint32_t size = *(volatile uint32_t*)(CP_PARAM + 2);
            print_d32(size);
            cpm_printstring("\r\n");
        }

        closedir();
    }
    return 0;
}