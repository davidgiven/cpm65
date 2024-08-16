static unsigned char byteop(void)
{
    register unsigned char i = 16;

    while (i--);
    return i;
}

static unsigned int preop(void)
{
    register unsigned i = 16;
    unsigned j = 0;

    while (i--)
        j++;
    return j;
}

static const char *str="01234567";

static unsigned int ptrop(void)
{
    register char *p = str;
    register unsigned n = 0;

    while (*p) {
        p++;
        n++;
    }
    return n;
}

int test_cast(void)
{	
    static int buf;
    register char *p = (char *)&buf;
    *(int *)p = 0x1234;
    return buf;
}

int main(int argc, char *argv[])
{
    register int x = 0;
    if (x != 0)
        return 1;
    while(x++ < 30);
    if (x != 31)
        return 2;
    if (byteop() != 0xFF)
        return 3;
    if (preop() != 16)
        return 4;
    if (ptrop() != 8)
        return 5;
    if (test_cast() != 0x1234)
        return 6;
    return 0;
}
