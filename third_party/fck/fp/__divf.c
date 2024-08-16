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

/* divide two floats */
uint32_t __divf(uint32_t a1, uint32_t a2)
{
	uint32_t result;
	uint32_t mask;
	uint32_t mant1, mant2;
	int exp;
	uint32_t sign;

	/* subtract exponents */
	exp = EXP(a1);
	exp -= EXP(a2);
	exp += EXCESS;

	/* compute sign */
	sign = SIGN(a1) ^ SIGN(a2);

	/* divide by zero??? */
	if (!a2) {		/* return NaN or -NaN */
		return 0x7FC00000UL;
	}

	/* numerator zero??? */
	if (!a1)
		return (0);

	/* now get mantissas */
	mant1 = MANT(a1);
	mant2 = MANT(a2);

	/* this assures we have 25 bits of precision in the end */
	if (mant1 < mant2) {
		mant1 <<= 1;
		exp--;
	}

	/* now we perform repeated subtraction of a2 from a1 */
	mask = 0x1000000UL;
	result = 0;
	while (mask) {
		if (mant1 >= mant2) {
			result |= mask;
			mant1 -= mant2;
		}
		mant1 <<= 1;
		mask >>= 1;
	}

	/* round */
	result += 1;

	/* normalize down */
	exp++;
	result >>= 1;

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
