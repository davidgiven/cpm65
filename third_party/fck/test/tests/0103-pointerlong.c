/*
 *	Some minimal pointer and increment
 *	checks on behaviour and return
 */

int main(int argc, char *argv[])
{
    long buf2[32];
    long *bp2 = buf2;

    /* With long */
    if (++ bp2 != buf2 + 1)
        return 1;
    bp2 = buf2;
    if (bp2 ++ != buf2)
        return 2;
    bp2 = buf2;
    if ((bp2 += 4) != buf2 + 4)
        return 3;
    /* Check scaling */
    if (((unsigned)bp2)!= (unsigned)buf2 + 16)
        return 4;
    /* Check subtraction scales */
    bp2 = buf2 + 37;
    if (bp2 - buf2 != 37)
        return 5;
    return 0;
}