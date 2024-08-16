/*
 * Derived from code
 *
** libgcc support for software floating point.
** Copyright (C) 1991 by Pipeline Associates, Inc.  All rights reserved.
** Permission is granted to do *anything* you want with this file,
** commercial or otherwise, provided this message remains intact.  So there!
** I would appreciate receiving any updates/patches/changes that anyone
** makes, and am willing to be the repository for said changes (am I
** making a big mistake?).
**
** Pat Wood
** Pipeline Associates, Inc.
** pipeline!phw@motown.com or
** sun!pipeline!phw or
** uunet!motown!pipeline!phw
*/

#include "libfp.h"

/* multiply two floats */
uint32_t __mulf(uint32_t a1, uint32_t a2)
{
	uint32_t result;
	int exp;
	uint32_t sign;

	if (!a1 || !a2)
		return (0);

	/* compute sign and exponent */
	sign = SIGN(a1) ^ SIGN(a2);
	exp = EXP(a1) - EXCESS;
	exp += EXP(a2);

	a1 = MANT(a1);
	a2 = MANT(a2);

	/* the multiply is done as one 16x16 multiply and two 16x8 multiples */
	result = (a1 >> 8) * (a1 >> 8);
	result += ((a1 & 0xFFUL) * (a2 >> 8)) >> 8;
	result += ((a2 & 0xFFUL) * (a1 >> 8)) >> 8;

	/* round, phase 1 */
	result += 0x40;

	if (result & SIGNBIT) {
		/* round, phase 2 */
		result += 0x40;
		result >>= 8;
	} else {
		result >>= 7;
		exp--;
	}

	result &= ~HIDDEN;

	/* pack up and go home */
	if (exp >= 0x100)
		a1 = (sign ? SIGNBIT : 0) | INFINITY;
	else if (exp < 0)
		a1 = 0;
	else
		a1 = PACK(sign ? SIGNBIT : 0, exp, result);
	return a1;
}
