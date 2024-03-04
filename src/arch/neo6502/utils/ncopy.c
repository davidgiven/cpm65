#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cpm.h>
#include "neo6502.h"

int main(int argc, const char* argv[])
{
    cpm_cmdline[cpm_cmdlinelen] = 0;

    const char* srcfile = getword();
    const char* destfile = getword();

    if (!srcfile || !destfile || *cmdptr)
         cpm_printstring("Syntax: ncopy <srcfile> <destfile>\r\n");
    else
    {
        cpm_printstring("Copying '");
        cpm_printstring(srcfile);
        cpm_printstring("' to '");
        cpm_printstring(destfile);
        cpm_printstring("'...\r\n");

        int srcfilelen = strlen(srcfile);
        char srcfilep[srcfilelen+1];
        srcfilep[0] = srcfilelen;
        memcpy(srcfilep+1, srcfile, srcfilelen);

        int destfilelen = strlen(destfile);
        char destfilep[destfilelen+1];
        destfilep[0] = destfilelen;
        memcpy(destfilep+1, destfile, destfilelen);

        while (CP_GROUP);

        CP_FUNCTION = FUNC_FILE_COPY;
        *(volatile void**)(CP_PARAM+0) = srcfilep;
        *(volatile void**)(CP_PARAM+2) = destfilep;
        CP_GROUP = GROUP_FILE;

        while (CP_GROUP);
        if (CP_ERRNO)
            cpm_printstring("Failed.\r\n");
        else
            cpm_printstring("Suceeded.\r\n");
    }

    return 0;
}