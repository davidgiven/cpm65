/*
 *	Some minimal pointer and increment
 *	checks on behaviour and return
 */

int main(int argc, char *argv[])
{
    char buf[32];
    char *bp = buf;
    int buf2[32];
    int *bp2 = buf2;

    /* Pre inc should return modifed value */
    if (++ bp != buf + 1)
        return 1;
    bp  = buf;
    /* Post inc should not */
    if (bp ++ != buf)
        return 2;
    bp  = buf;
    /* += should */
    if ((bp += 4) != buf + 4)
        return 3;

    /* Same with words */
    if (++ bp2 != buf2 + 1)
        return 4;
    bp2 = buf2;
    if (bp2 ++ != buf2)
        return 5;
    bp2 = buf2;
    if ((bp2 += 4) != buf2 + 4)
        return 6;
    /* Check scaling */
    if (((unsigned)bp2)!= (unsigned)buf2 + 8)
        return 7;
    /* Check subtraction scales */
    bp2 = buf2 + 37;
    if (bp2 - buf2 != 37)
        return 8;
    return 0;
}