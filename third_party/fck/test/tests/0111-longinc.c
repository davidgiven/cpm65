
int main(int argc, char *argv[])
{
    long a = 0;
    if (++a != 1)
        return 1;
    if (a++ != 1)
        return 2;
    if (a-- != 2)
        return 3;
    if (--a)
        return 4;
    if ((a += 12) != 12)
        return 5;
    if ((a -= 12) != 0)
        return 6;
    if ((a += 0x20000) != 0x20000)
        return 7;
    if (a != 0x20000)
        return 8;
    if ((a -= 0x20000) != 0)
        return 9;
    if (a != 0)
        return 10;
    return 0;
}