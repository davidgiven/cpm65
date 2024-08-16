
static int sx = 300;
static int sy = 400;

int main(int argc, char *argv[])
{
    int i;
    int j;
    int n = 0;
    for (i = (sx / 100) - 1; i < (sx / 100) + 1; i++) {
        for (j = (sy / 100) - 1; j < (sy / 100) + 1; j++) {
            n++;
            if (n > 100)
                return 2;
        }
    }
    if (n != 4)
        return 1;

    n = 0;
    for (i = (sx / 100) - 1; i <= (sx / 100) + 1; i++) {
        for (j = (sy / 100) - 1; j <= (sy / 100) + 1; j++) {
            n++;
            if (n > 100)
                return 3;
        }
    }
    if (n != 9)
        return 4;
    return 0;
}

