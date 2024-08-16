#/*
 *	unsigned integer comparisons
 */
int test_ult(unsigned int a, unsigned int b)
{
    return a < b;
}

int test_ult8(unsigned char a, unsigned char b)
{
    return a < b;
}

int test_ugt(unsigned int a, unsigned int b)
{
    return a > b;
}

int test_ugt8(unsigned char a, unsigned char b)
{
    return a > b;
}

int test_ule(unsigned int a, unsigned int b)
{
    return a <= b;
}

int test_ule8(unsigned char a, unsigned char b)
{
    return a <= b;
}

int test_uge(unsigned int a, unsigned int b)
{
    return a >= b;
}

int test_uge8(unsigned char a, unsigned char b)
{
    return a >= b;
}

static unsigned x = 12;
static unsigned char y = 12;

int main(int argc, char *argv[])
{
    unsigned n;
    unsigned char m;
    if (test_ult(33, 11) == 1)
        return 1;
    if (test_ult(32769U, 11U) == 1)
        return 2;
    if (test_ult(49151U, 54545U) == 0)
        return 3;
    if (test_ult(17, 27) == 0)
        return 4;
    if (test_ult(12345,12345) == 1)
        return 5;
    if (test_ult8(33, 11) == 1)
        return 6;
    if (test_ult8(254, 11) == 1)
        return 7;
    if (test_ult8(231, 255) == 0)
        return 8;
    if (test_ult8(17, 27) == 0)
        return 9;
    if (test_ult8(12,12) == 1)
        return 10;


    if (test_ugt(33, 11) == 0)
        return 11;
    if (test_ugt(32769U, 11U) == 0)
        return 12;
    if (test_ugt(49151U, 54545U) == 1)
        return 13;
    if (test_ugt(17, 27) == 1)
        return 14;
    if (test_ugt(12345,12345) == 1)
        return 15;
    if (test_ugt8(33, 11) == 0)
        return 16;
    if (test_ugt8(254, 11) == 0)
        return 17;
    if (test_ugt8(231, 255) == 1)
        return 18;
    if (test_ugt8(17, 27) == 1)
        return 19;
    if (test_ugt8(12,12) == 1)
        return 20;

    if (test_uge(33, 11) == 0)
        return 21;
    if (test_uge(32769U, 11U) == 0)
        return 22;
    if (test_uge(49151U, 54545U) == 1)
        return 23;
    if (test_uge(17, 27) == 1)
        return 24;
    if (test_uge(12345,12345) == 0)
        return 25;
    if (test_uge8(33, 11) == 0)
        return 26;
    if (test_uge8(254, 11) == 0)
        return 27;
    if (test_uge8(231, 255) == 1)
        return 28;
    if (test_uge8(17, 27) == 1)
        return 29;
    if (test_uge8(12,12) == 0)
        return 30;

    if (test_ule(33, 11) == 1)
        return 31;
    if (test_ule(32769U, 11U) == 1)
        return 32;
    if (test_ule(49151U, 54545U) == 0)
        return 33;
    if (test_ule(17, 27) == 0)
        return 34;
    if (test_ule(12345,12345) == 0)
        return 35;
    if (test_ule8(33, 11) == 1)
        return 36;
    if (test_ule8(254, 11) == 1)
        return 37;
    if (test_ule8(231, 255) == 0)
        return 38;
    if (test_ule8(17, 27) == 0)
        return 39;
    if (test_ule8(12,12) == 0)
        return 40;

    /* cc tests */
    n = 12;
    if (n < 12)
        return 41;
    if (n > 12)
        return 42;
    if (n <= 11)
        return 43;
    if (n >= 13)
        return 44;
    /* Static cc tests */
    if (x > 12)
        return 45;
    if (x >= 13)
        return 46;
    if (x < 12)
        return 47;
    if (x <= 11)
        return 48;

    /* Byte */

    /* cc tests */
    m = 12;
    if (m < 12U)
        return 49;
    if (m > 12U)
        return 50;
    if (m <= 11U)
        return 51;
    if (m >= 13U)
        return 52;

    /* Static cc tests */
    if (y > 12U)
        return 53;
    if (y >= 13U)
        return 54;
    if (y < 12U)
        return 55;
    if (y <= 11U)
        return 56;

    return 0;
}
