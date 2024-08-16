
unsigned long and(unsigned long a, unsigned long b)
{
    return a & b;
}

unsigned long or(unsigned long a, unsigned long b)
{
    return a | b;
}

unsigned long xor(unsigned long a, unsigned long b)
{
    return a ^ b;
}

unsigned long bitflip(unsigned long a)
{
    return ~a;
}

unsigned long andeq(unsigned long a, unsigned long b)
{
    return a &= b;
}

unsigned long oreq(unsigned long a, unsigned long b)
{
    return a |= b;
}

unsigned long xoreq(unsigned long a, unsigned long b)
{
    return a ^= b;
}

int main(int argc, char *argv[])
{
    if (and(0xFFFFF000, 0x0000FFFF) != 0x0000F000)
        return 1;
    if (xor(0xFF00FF00, 0x00FF00FF) != 0xFFFFFFFF)
        return 2;
    if (or(0x55AA55AA, 0xAA55AA55) != 0xFFFFFFFF)
        return 3;
    if (bitflip(0xAAAAAAAA) != 0x55555555)
        return 4;
    if (andeq(0xFFFFF000, 0x0000FFFF) != 0x0000F000)
        return 5;
    if (xoreq(0xFF00FF00, 0x00FF00FF) != 0xFFFFFFFF)
        return 6;
    if (oreq(0x55AA55AA, 0xAA55AA55) != 0xFFFFFFFF)
        return 7;
    return 0;
}