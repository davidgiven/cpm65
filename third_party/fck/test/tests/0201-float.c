/*
 *	unsigned integer comparisons
 */
int test_flt(float a, float b)
{
    return a < b;
}

int test_fgt(float a, float b)
{
    return a > b;
}

int test_fle(float a, float b)
{
    return a <= b;
}

int test_fge(float a, float b)
{
    return a >= b;
}

int about(float a, float b)
{
    float x = a - b;
    if (x < -0.01 || x > 0.01)
        return 0;
    return 1;
}

int main(int argc, char *argv[])
{
    if (test_flt(33.6, 11.4) == 1)
        return 1;
    if (test_fgt(33.6, 11.4) == 0)
        return 2;
    if (test_fge(33.6, 11.4) == 0)
        return 3;
    if (test_fle(33.6, 11.4) == 1)
        return 4;
    if (test_flt(-1.2, 1.1) == 0)
        return 5;
    if (test_fgt(1.1, -1.2) == 0)
        return 6;
    if (test_fge(-1.2, 1.1) == 1)
        return 7;
    if (test_fle(1.1, -1.2) == 1)
        return 8;
    /* These will need changing if the front end learns to optimize
       const float math */
    if (0.0 + 0.0 != 0.0)
        return 9;
    if (0.0 - 0.0 != 0.0)
        return 10;
    if (!about(0.0, 0.0))
        return 11;
    if (!about(4.1, 4.1))
        return 12;
    if (!about(0.1001, 0.1))
        return 13;
    if (!about(0.101 + 0.01, 0.111))
        return 14;
    if (!about(12.5 + 2.1, 14.6))
        return 15;
    if (!about(12.5 - 2.1, 10.4))
        return 16;
    if (!about(2.0 * 4.0, 8.0))
        return 17;
    if (!about(2.0 / 4.0, 0.5))
        return 18;
    if (about(0.1, 5.0))
        return 19;
    return 0;
}
