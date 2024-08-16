#include "libfp.h"

unsigned long __castf_ul(uint32_t a1)
{
    if (a1 & 0x7FFFFFFFUL)
        return MANT(a1) >> (EXP(a1) - EXCESS - 24);
    return 0;
}

unsigned __castf_u(uint32_t a1)
{
    if (a1 & 0x7FFFFFFFUL)
        return MANT(a1) >> (EXP(a1) - EXCESS - 24);
    return 0;
}

unsigned char __castf_uc(uint32_t a1)
{
    if (a1 & 0x7FFFFFFFUL)
        return MANT(a1) >> (EXP(a1) - EXCESS - 24);
    return 0;
}

long __castf_l(uint32_t a1)
{
    if (a1 == 0)
        return 0;
    if (a1 & 0x80000000)
        return -__castf_ul(__negatef(a1));
    return __castf_ul(a1);
}

int __castf_(uint32_t a1)
{
    return __castf_l(a1);
}

signed char __castf_c(uint32_t a1)
{
    return __castf_l(a1);
}
