/*
 *	IEEE floats have a sign bit so this is trivial
 *
 *	Need to deal with all the nan etc corner cases maybe
 */

#include "libfp.h"

uint32_t __negatef(uint32_t a)
{
    a ^= 0x80000000;
}

uint32_t __minusf(uint32_t a1, uint32_t a2)
{
    uint32_t r = __negatef(a1);
    return __negatef(r + a2);
}
