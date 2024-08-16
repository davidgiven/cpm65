/*
 *	Signed integer comparisons.
 *	Check each quadrant
 */

int test_lt(int a, int b)
{
    return a < b;
}

int test_lt8(signed char a, signed char b)
{
    return a < b;
}

static unsigned x = 12;

int main(int argc, char *argv[])
{
    int n;
    /* Both positive */
    if (test_lt(33, 11) == 1)
        return 1;
    /* Both negative */
    if (test_lt(-4, -7) == 1)
        return 2;
    /* +ve / -ve */
    if (test_lt(39, -32767) == 1)
        return 3;
    /* -ve / +ve */
    if (test_lt(-1, 5) == 0)
        return 4;
    /* zero */
    if (test_lt(-1, 0) == 0)
        return 5;
    if (test_lt(0, -1) == 1)
        return 6;
    /* Both positive */
    if (test_lt8(33, 11) == 1)
        return 7;
    /* Both negative */
    if (test_lt8(-4, -7) == 1)
        return 8;
    /* +ve / -ve */
    if (test_lt8(39, -127) == 1)
        return 9;
    /* -ve / +ve */
    if (test_lt8(-1, 5) == 0)
        return 10;
    /* zero */
    if (test_lt8(-1, 0) == 0)
        return 11;
    if (test_lt8(0, -1) == 1)
        return 12;
    /* cc tests */
    n = 12;
    if (n < 12)
        return 13;
    if (n > 12)
        return 14;
    if (n <= 11)
        return 15;
    if (n >= 13)
        return 16;
    n = -15;
    if (n < -15)
        return 17;
    if (n > -15)
        return 18;
    if (n > 4)
        return 19;
    if (n >= -14)
        return 20;
    if (n <= -16)
        return 21;
    n = 20000;
    if (n < -1)
        return 22;
    if (n < 20000)
        return 23;
    if (n > 20000)
        return 24;
    if (n >= 20001)
        return 25;
    if (n <= 19999)
        return 26;
    n = -5;
    if (n > 0)
        return 27;
    if (n >= 0)
        return 28;
    n = 5;
    if (n <= 0)
        return 29;
    if (n < 0)
        return 30;
    n = 0;
    if (n > 0)
        return 31;
    if (n < 0)
        return 32;
    if (!(n >= 0))
        return 33;
    if (!(n <= 0))
        return 34;
    /* Subtracts are helper driven on some cpus so check */
    if (n - 5 != -5)
        return 35;
    n = 12;
    if (n - 12)
        return 36;
    if ((n - -6) != 18)
        return 37;
    /* Static cc tests */
    if (x > 12)
        return 38;
    if (x >= 13)
        return 39;
    if (x < 12)
        return 40;
    if (x <= 11)
        return 41;
    return 0;
}
