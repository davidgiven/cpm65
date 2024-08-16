/*
 * Dervied from code
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

/* add two floats. We express them entirely as 32bi unsigned as we don't
   want to cause any recursive fp ops! */
uint32_t __plusf(uint32_t a1, uint32_t a2)
{
	uint32_t mant1, mant2;
	int exp1, exp2, expd;
	uint32_t sign = 0;

	exp2 = EXP(a2);
	mant2 = MANT(a2) << 4;
	if (SIGN(a2))
		mant2 = -mant2;
	/* check for zero args */
	if (!a2)
		return (a1);

	exp1 = EXP(a1);
	mant1 = MANT(a1) << 4;
	if (SIGN(a1))
		if (a1 & 0x80000000UL)
			mant1 = -mant1;
	/* check for zero args */
	if (!a1)
		return (a2);

	expd = exp1 - exp2;
	if (expd > 25)
		return (a1);
	if (expd < -25)
		return (a2);

	if (expd < 0) {
		expd = -expd;
		exp1 += expd;
		mant1 >>= expd;
	} else {
		mant2 >>= expd;
	}
	mant1 += mant2;

	sign = 0;

	if (mant1 & 0x80000000UL) {
		mant1 = -mant1;
		sign = 1;
	} else if (!mant1)
		return (0);

	/* normalize */
	while (mant1 < (HIDDEN << 4)) {
		mant1 <<= 1;
		exp1--;
	}

	/* round off */
	while (mant1 & 0xf0000000) {
		if (mant1 & 1)
			mant1 += 2;
		mant1 >>= 1;
		exp1++;
	}

	/* turn off hidden bit */
	mant1 &= ~(HIDDEN << 4);

	/* pack up and go home */
	if (exp1 >= 0x100)
		a1 = (sign ? (SIGNBIT | INFINITY) : INFINITY);
	else if (exp1 < 0)
		a1 = 0;
	else
		a1 = PACK(sign ? SIGNBIT : 0, exp1, mant1 >> 4);
	return (a1);
}
