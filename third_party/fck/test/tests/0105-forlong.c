int main(int argc, char *argv[])
{
    long i;
    for (i = 0; i < 100000; i++) {
        if (i == 50000)
            break;
    }
    if (i != 50000)
        return 1;
    return 0;
}
