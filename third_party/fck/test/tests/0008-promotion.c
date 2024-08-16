
int func(signed char a)
{
    return a;
}

int main(int argc, char *argv[])
{
    signed char a;
    int b;

    a = 0xA5;
    b = a;
    if ((unsigned)b != 0xFFA5)
        return 1;

    b = 0x1234;
    a = b;
    if (a != 0x34)
        return 2;

    a = 0xAB;
    if ((unsigned)func(a) != 0xFFAB)
        return 3;
    a = 0x20;
    if ((unsigned)func(a) != 0x0020)
        return 4;
    return 0;
}

    