int main(int argc, char *argv[])
{
    int i;
    for (i = 0; i < 100; i++) {
        if (i == 50)
            break;
    }
    if (i != 50)
        return 1;
    return 0;
}
