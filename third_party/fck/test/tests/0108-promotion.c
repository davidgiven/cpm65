
long func(int a)
{
    return a;
}

int main(int argc, char *argv[])
{
    int a;
    long b;

    a = 0xA5A5;
    b = a;
    if ((unsigned long)b != 0xFFFFA5A5)
        return 1;

    b = 0x12345678;
    a = b;
    if (a != 0x5678)
        return 2;

    a = 0xABCD;
    if ((unsigned long)func(a) != 0xFFFFABCD)
        return 3;
    a = 0x2000;
    if ((unsigned long)func(a) != 0x00002000)
        return 4;
    return 0;
}

    