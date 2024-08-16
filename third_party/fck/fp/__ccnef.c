#include "libfp.h"

/* TODO; check rules on NaN etc */

unsigned __ccnef(uint32_t a1, uint32_t a2)
{
    if (a1 == a2)
        return 0;
    if ((a1 | a2) & 0x7FFFFFFFUL)
        return 1;
    return 0;
}
