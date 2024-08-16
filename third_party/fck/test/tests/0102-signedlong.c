/*
 *	Signed long comparisons.
 *	Check each quadrant
 *
 *	TODO: add tests that tickle the various
 *	low similar/high different paths
 */

long test_lt(long a, long b)
{
    return a < b;
}

long test_gt(long a, long b)
{
    return a > b;
}

int main(int argc, char *argv[])
{
    int n;
    long x;
    /* Both positive */
    if (test_lt(0x30301110, 0x00001110) == 1)
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
    x = 4413;
    if (-x != -4413)
        return 7;
    n = -12;
    if (((long)n) != -12L)
        return 8;
    if (test_gt(0, -1) == 0)
        return 9;
    if (test_gt(-1, 1) == 1)
        return 10;
    if (test_gt(5, 1) == 0)
        return 11;
    if (test_gt(-5, -1) == 1)
        return 12;
    return 0;
}
