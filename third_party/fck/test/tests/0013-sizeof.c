
char a;
int b;
long c;
float d;
double e;
char *f;
int *g;
long *h;
float *i;
double *j;

char k[6];
long l[4];
char m[] = "Hello";

int main(int argc, char *argv[])
{
    if (sizeof(char) != 1)
        return 1;
    if (sizeof(short) != 2)
        return 2;
    if (sizeof(long) != 4)
        return 3;
    if (sizeof(char *) != 2)
        return 4;
    if (sizeof(int *) != 2)
        return 5;
    if (sizeof(long *) != 2)
        return 6;
    if (sizeof(unsigned char) != 1)
        return 7;
    if (sizeof(unsigned short) != 2)
        return 8;
    if (sizeof(unsigned long) != 4)
        return 9;
    if (sizeof(unsigned char *) != 2)
        return 10;
    if (sizeof(unsigned int *) != 2)
        return 11;
    if (sizeof(unsigned long *) != 2)
        return 12;
    if (sizeof(a) != 1)
        return 13;
    if (sizeof(b) != 2)
        return 14;
    if (sizeof(c) != 4)
        return 15;
    if (sizeof(f) != 2)
        return 16;
    if (sizeof(g) != 2)
        return 17;
    if (sizeof(h) != 2)
        return 18;

    if (sizeof(float) != 4)
        return 19;
    if (sizeof(double) != 4)
        return 20;
    if (sizeof(d) != 4)
        return 21;
    if (sizeof(e) != 4)
        return 22;
    if (sizeof(i) != 2)
        return 23;
    if (sizeof(j) != 2)
        return 24;

    if (sizeof(k) != 6)
        return 25;
    if (sizeof(l) != 16)
        return 26;
    if (sizeof(m) != 6)
        return 27;

    /* And the funny one */
    if (sizeof("Hello") != 6)
        return 28;

    return 0;
}
