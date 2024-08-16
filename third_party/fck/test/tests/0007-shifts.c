

int left4(unsigned x)
{
    return x << 4;
}

int right4(int x)
{
    return x >> 4;
}

int lshift(unsigned x, unsigned y)
{
    return x << y;
}

int rshiftu(unsigned x, unsigned y)
{
    return x >> y;
}

int rshifts(int x, unsigned y)
{
    return x >> y;
}

unsigned uint;
int sint;
unsigned char uchr;
signed char chr;

int main(int argc, char *argv[])
{
    if (left4(2) != 32)
        return 1;
    if (right4(32) != 2)
        return 2;
    if (right4(0x8000) != 0xF800)
        return 3;
    if (lshift(0x55, 8) != 0x5500)
        return 4;
    if (rshiftu(0x3000, 12) != 0x03)
        return 5;
    if (rshifts(0x3000, 12) != 0x03)
        return 6;
    if (rshifts(0x8000, 12) != 0xFFF8)
        return 7;
    if (rshifts(12, 0) != 12)
        return 8;
    if (lshift(0x55AA, 0) != 0x55AA)
        return 9;

    sint = 4;
    sint >>= 2;
    if (sint != 1)
        return 10;
    sint = 0xFFFE;
    sint >>= 1;
    if (sint != 0xFFFF)
        return 11;

    uint = 0xC000;
    uint >>= 4;
    if (uint != 0x0C00)
        return 12;
    chr = 4;
    chr >>= 2;
    if (chr != 1)
        return 13;
    chr = -2;
    chr >>= 1;
    if (chr != -1)
        return 14;
    uchr = 0xC0;
    uchr >>= 4;
    if (uchr != 0x0C)
        return 15;
    return 0;

    sint = 4;
    sint >>= 0;
    if (sint != 4)
        return 16;
    uint = 0xC000;
    uint >>= 0;
    if (uint != 0xC000)
        return 17;
    chr = -2;
    chr >>= 0;
    if (chr != -2)
        return 18;
    uchr = 0xC0;
    uchr >>= 0;
    if (uchr != 0xC0)
        return 19;
    return 0;

}
