
int main(int argc, char *argv[])
{
    unsigned r = 0;
    int i;
    unsigned char j;
    /* do an unmatched case, all the cases and a fall through check */
    for (i = 0; i <= 10; i++) {
        switch(i) {
        case 1:
            r ^= 0x01;
            break;
        case 2:
            r ^= 0x02;
            break;
        case 3:
            r ^= 0x04;
            break;
        case 4:
            r ^= 0x08;
            break;
        case 5:
            r ^= 0x10;
            break;
        case 6:
            r ^= 0x20;
            break;
        case 7:
            r ^= 0x40;
            break;
        case 8:
            r ^= 0x80;
            break;
        case 9:
            r ^= 0x100;
            break;
        case 10:
            r ^= 0x200;
            /* fall through test */
        case 11:
            r ^= 0xFC00;
        }
    }
    if (r != 0xFFFF)
        return 1;

    r = 0;

    for (j = 1; j <= 8; j++) {
        switch(j) {
        case 1:
            r ^= 0x01;
            break;
        case 2:
            r ^= 0x02;
            break;
        case 3:
            r ^= 0x04;
            break;
        case 4:
            r ^= 0x08;
            break;
        case 5:
            r ^= 0x10;
            break;
        case 6:
            r ^= 0x20;
            break;
        case 7:
            r ^= 0x40;
            break;
        case 8:
            r ^= 0x80;
            break;
        }
    }
    if (r != 0xFF)
        return 2;
    return 0;
}

