

int count_bits(unsigned x)
{
    unsigned i = 1;
    int n = 0;
    int c;

    for (c = 0; c < 16; c++) {
        if (x & i)
            n++;
        i <<= 1;
    }
    return n;
}

int main(int argc, char *argv[])
{
    if (count_bits(0x5555) != 8)
        return 1;
    if (count_bits(0x0000) != 0)
        return 2;
    if (count_bits(0x00FF) != 8)
        return 3;
    if (count_bits(0xFF00) != 8)
        return 4;
    if (count_bits(0xFFFF) != 16)
        return 5;
    return 0;
}