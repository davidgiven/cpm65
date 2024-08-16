
long mul(long a, long b)
{
    return a * b;
}

unsigned long divu(unsigned long a, unsigned long b)
{
    return a / b;
}

unsigned long modu(unsigned long a, unsigned long b)
{
    return a % b;
}

long divs(long a, long b)
{
    return a / b;
}

long mods(long a, long b)
{
    return a % b;
}

int main(int argc, char *argv[])
{
    unsigned long n;
    long i;
    if (mul(0xFF,0xFF) != 65025U)
        return 1;
    if (mul(0xFF,0) != 0)
        return 2;
    if (divu(200, 10) != 20)
        return 3;
    if (divu(10, 10) != 1)
        return 4;
    if (divu(209, 10) != 20)
        return 5;
    if (divs(200, 10) != 20)
        return 6;
    if (divs(200, -10) != -20)
        return 7;
    if (divs(-200, 10) != -20)
        return 8;
    if (modu(1000, 10) != 0)
        return 9;
    if (modu(1005, 10) != 5)
        return 10;
    if (mods(1000, 10) != 0)
        return 11;
    if (mods(1006, 10) != 6)
        return 12;
    if (mods(-1006, 10) != -6)
        return 13;
    if (mods(-1006, -10) != -6)
        return 14;
    if (mods(1006, -10) != 6)
        return 15;
    n = 32;
    n /= 4;
    if (n != 8)
        return 16;
    n %= 12;
    if (n != 8)
        return 17;
    i = -32;
    i /= 4;
    if (i != -8)
        return 18;
    i %= 10;
    if (i != -8)
        return 19;
    return 0;
}
