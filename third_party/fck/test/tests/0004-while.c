

int main(int argc, char *argv[])
{
    unsigned n = 0;
    unsigned c = 0;

    while (n++ < 100)
        c++;
    if (c != 100)
        return 1;

    c = 0;
    do {
        c++;
    } while(0);
    if (c != 1)
        return 2;

    n = 0;
    c = 0;
    do {
        c++;
    } while(n++ < 30);
    if (c != 31)
        return 3;

    n = 0;
    c = 0;
    while(n++ < 50) {
        if (n == 1)
            continue;
        c++;
        if (n == 25)
            break;
    }
    if (c != 24)
        return 4;
    return 0;
}

