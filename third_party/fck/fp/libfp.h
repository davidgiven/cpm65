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

/* FIXME: sort out compiler supplied include */
typedef unsigned long	uint32_t;

#define HIDDEN		(1UL << 23)	/* Implied 1 bit in IEE float */
#define SIGN(x)		(((x) >> 31) & 0x01)
#define EXP(x)		(((x) >> 23) & 0xFF)
#define MANT(x)		(((x) & 0x7FFFFF) | HIDDEN)

#define SIGNBIT		0x80000000UL
#define INFINITY	0x78000000UL

#define PACK(s, e, m)	((s) | (((uint32_t)(e)) << 23) | ((m) & 0x7FFFFFUL))

#define EXCESS		126

/*
 *	Routines provided to the compiler core (and to each other)
 */

extern uint32_t __negatef(uint32_t);
extern uint32_t __minusf(uint32_t, uint32_t);
extern uint32_t __plusf(uint32_t, uint32_t);
extern uint32_t __mulf(uint32_t, uint32_t);
extern uint32_t __divf(uint32_t, uint32_t);

extern unsigned __cceqf(uint32_t, uint32_t);
extern unsigned __ccnef(uint32_t, uint32_t);
extern unsigned __ccltf(uint32_t, uint32_t);
extern unsigned __ccgtf(uint32_t, uint32_t);
extern unsigned __cclteqf(uint32_t, uint32_t);
extern unsigned __ccgteqf(uint32_t, uint32_t);

extern unsigned char __castf_uc(uint32_t);
extern unsigned __castf_u(uint32_t);
extern unsigned long __castf_ul(uint32_t);

extern signed char __castf_c(uint32_t);
extern int __castf_(uint32_t);
extern long __castf_l(uint32_t);

extern uint32_t __castuc_f(unsigned char);
extern uint32_t __castu_f(unsigned int);
extern uint32_t __castul_f(unsigned long);

extern uint32_t __castc_f(signed char);
extern uint32_t __cast_f(int);
extern uint32_t __castl_f(long);
