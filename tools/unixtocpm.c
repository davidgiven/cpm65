#include <stdio.h>
#include <stdlib.h>

int main(int argc, const char* argv[])
{
    for (;;)
    {
        int c = getchar();
        if ((c == -1) || (c == 26))
            break;
        if (c == '\n')
            putchar('\r');
        if (c != '\r')
            putchar(c);
    }
    putchar(26);

    return 0;
}
