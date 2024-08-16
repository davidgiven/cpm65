
int x[8][8];
char y[8][8];
int z[8];

int main(int argc, char *argv[])
{
    int *p = (int *)x;
    char *q = (char *)y;
    int *r = z;

    if (sizeof(z) != 16)
        return 1;
    if (r != &z[0])
        return 2;
    z[0] = 1;
    if (*r != 1)
        return 3;
    z[0]++;
    if (*r != 2)
        return 4;

    if (sizeof(x) != 128)
        return 5;
    if (sizeof(y) != 64)
        return 6;

    if (p != &x[0][0])
        return 7;
    x[0][0] = 1;
    if (*p != 1)
        return 8;
    x[0][0]++;
    if (*p != 2)
        return 9;

    if (q != &y[0][0])
        return 10;
    y[0][0] = 1;
    if (*q != 1)
        return 11;
    y[0][0]++;
    if (*q != 2)
        return 12;

    return 0;
}

