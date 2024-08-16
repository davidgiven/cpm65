
unsigned int x[6] = { 11, 335, 4481, -22, 86, 5 };

int main(int argc, char *argv[])
{
    unsigned int *p = x;
    int n = 0;
    while(p != &x[6])
        n += *p++;
    if (n != 4896)
        return 1;
    x[3] = 0;
    n = 0;
    p = x;
    while(p != &x[6])
        n += *p++;
    if (n != 4918)
        return 2;
    return 0;
}
