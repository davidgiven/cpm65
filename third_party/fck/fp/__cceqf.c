#include "libfp.h"

/* TODO; check rules on NaN etc */

unsigned __cceqf(uint32_t a1, uint32_t a2)
{
    if (a1 == a2)
        return 1;
    if ((a1 | a2) & 0x7FFFFFFFUL)
        return 0;
    return 1;
}
