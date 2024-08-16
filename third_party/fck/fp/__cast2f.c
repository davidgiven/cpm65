#include "libfp.h"

uint32_t __castul_f(unsigned long a1)
{
    int exp = 24 + EXCESS;
    if (a1 == 0)
        return 0;		/* Float 0 is the same */
    /* Move down until our first one bit is the implied bit */
    while(a1 & 0xFF000000UL) {
        exp++;
        a1 >>= 1;
    }
    /* Move smaller numbers up until the first 1 bit is in the implied 1
       position */
    while(!(a1 & 0x01000000)) {
        exp--;
        a1 <<= 1;
    }
    /* And assemble */
    return PACK(0, exp, a1);
}

/* We could just use the uint32_t helper but 16bit is actually much simpler */
uint32_t __castu_f(unsigned a1)
{
    uint32_t r;
    int exp = 24 + EXCESS;

    if (a1 == 0)
        return a1;
    r = a1;
    while(!(r & 0x01000000)) {
        exp--;
        r <<= 1;
    }
    return PACK(0, exp, r);
}

uint32_t __castuc_f(unsigned char a1)
{
    uint32_t r;
    int exp = 24 + EXCESS;

    if (a1 == 0)
        return a1;
    r = a1;
    while(!(r & 0x01000000)) {
        exp--;
        r <<= 1;
    }
    return PACK(0, exp, r);
}

uint32_t __castl_f(long a1)
{
    if (a1 < 0)
        return __negatef(__castul_f(-a1));
    return __castul_f(a1);
}

uint32_t __cast_f(int a1)
{
    if (a1 < 0)
        return __negatef(__castu_f(-a1));
    return __castu_f(a1);
}

uint32_t __castc_f(signed char a1)
{
    if (a1 < 0)
        return __negatef(__castuc_f(-a1));
    return __castuc_f(a1);
}
