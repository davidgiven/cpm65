/*
 *	unsigned long comparisons
 */

long test_ult(unsigned long a, unsigned long b)
{
    return a < b;
}

long test_ult8(unsigned char a, unsigned char b)
{
    return a < b;
}

long test_ugt(unsigned long a, unsigned long b)
{
    return a > b;
}

long test_ule(unsigned long a, unsigned long b)
{
    return a <= b;
}

long test_uge(unsigned long a, unsigned long b)
{
    return a >= b;
}

int main(int argc, char *argv[])
{
    if (test_ult(33, 11) == 1)
        return 1;
    if (test_ult(0xFFFF0000UL, 0xFFUL) == 1)
        return 2;
    if (test_ult(0x0000FFFFUL, 0xFF00FF00UL) == 0)
        return 3;
    if (test_ult(0xFF, 0xFF0000) == 0)
        return 4;
    if (test_ult(0xFFEEDDCC,0xFFEEDDCC) == 1)
        return 5;

    if (test_ugt(0xFFFF0000UL, 0xFFUL) == 0)
        return 6;
    if (test_ugt(0x0000FFFFUL, 0xFF00FF00UL) == 1)
        return 7;
    if (test_ugt(0xFF, 0xFF0000) == 1)
        return 8;
    if (test_ugt(0xFFEEDDCC, 0xFFEEDDCC) == 1)
        return 9;

    if (test_uge(33, 11) == 0)
        return 11;
    if (test_uge(0xFFFF0000UL, 0xFFUL) == 0)
        return 12;
    if (test_uge(0x0000FFFFUL, 0xFF00FF00UL) == 1)
        return 13;
    if (test_uge(0xFF, 0xFF0000) == 1)
        return 14;
    if (test_uge(0xFFEEDDCC, 0xFFEEDDCC) == 0)
        return 15;

    if (test_ule(33, 11) == 1)
        return 11;
    if (test_ule(0xFFFF0000UL, 0xFFUL) == 1)
        return 12;
    if (test_ule(0x0000FFFFUL, 0xFF00FF00UL) == 0)
        return 13;
    if (test_ule(0xFF, 0xFF0000) == 0)
        return 14;
    if (test_ule(0xFFEEDDCC, 0xFFEEDDCC) == 0)
        return 15;

    return 0;
}
