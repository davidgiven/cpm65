
unsigned long x[6] = { 100000, 250000, 3000, -1000, 500, 12 };

int main(int argc, char *argv[])
{
    unsigned long *p = x;
    long n = 0;
    while(p != &x[6])
        n += *p++;
    if (n != 352512)
        return 1;
    x[3] = 0;
    n = 0;
    p = x;
    while(p != &x[6])
        n += *p++;
    if (n !=  353512)
        return 2;
    return 0;
}
