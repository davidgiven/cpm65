/* lib6502.c -- MOS Technology 6502 emulator	-*- C -*- */

/* Copyright (c) 2005 Ian Piumarta
 * 
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the 'Software'),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, provided that the above copyright notice(s) and this
 * permission notice appear in all copies of the Software and that both the
 * above copyright notice(s) and this permission notice appear in supporting
 * documentation.
 *
 * THE SOFTWARE IS PROVIDED 'AS IS'.  USE ENTIRELY AT YOUR OWN RISK.
 */

/* Last edited:
 * 
 * BUGS:
 *   - RTS and RTI do not check the return address for a callback
 *   - the disassembler cannot be configured to read two bytes for BRK
 *   - architectural variations (unimplemented/extended instructions) not implemented
 *   - ANSI versions (from from gcc extensions) of the dispatch macros are missing
 *   - emulator+disassembler in same object file (library is kind of pointless)
 */

#include <stdio.h>
#include <stdlib.h>

#include "lib6502.h"

typedef uint8_t  byte;
typedef uint16_t word;

enum {
  flagN= (1<<7),	/* negative 	 */
  flagV= (1<<6),	/* overflow 	 */
  flagX= (1<<5),	/* unused   	 */
  flagB= (1<<4),	/* irq from brk  */
  flagD= (1<<3),	/* decimal mode  */
  flagI= (1<<2),	/* irq disable   */
  flagZ= (1<<1),	/* zero          */
  flagC= (1<<0)		/* carry         */
};

#define getN()	(P & flagN)
#define getV()	(P & flagV)
#define getB()	(P & flagB)
#define getD()	(P & flagD)
#define getI()	(P & flagI)
#define getZ()	(P & flagZ)
#define getC()	(P & flagC)

#define setNVZC(N,V,Z,C)	(P= (P & ~(flagN | flagV | flagZ | flagC)) | (N) | ((V)<<6) | ((Z)<<1) | (C))
#define setNZC(N,Z,C)		(P= (P & ~(flagN |         flagZ | flagC)) | (N) |            ((Z)<<1) | (C))
#define setNZ(N,Z)		(P= (P & ~(flagN |         flagZ        )) | (N) |            ((Z)<<1)      )
#define setZ(Z)			(P= (P & ~(                flagZ        )) |                  ((Z)<<1)      )
#define setC(C)			(P= (P & ~(                        flagC)) |                             (C))

#define NAND(P, Q)	(!((P) & (Q)))

#define tick(n)
#define tickIf(p)

/* memory access (indirect if callback installed) -- ARGUMENTS ARE EVALUATED MORE THAN ONCE! */

#define putMemory(ADDR, BYTE)			\
  ( writeCallback[ADDR]				\
      ? writeCallback[ADDR](mpu, ADDR, BYTE)	\
      : (memory[ADDR]= BYTE) )

#define getMemory(ADDR)				\
  ( readCallback[ADDR]				\
      ?  readCallback[ADDR](mpu, ADDR, 0)	\
      :  memory[ADDR] )

/* stack access (always direct) */

#define push(BYTE)		(memory[0x0100 + S--]= (BYTE))
#define pop()			(memory[++S + 0x0100])

/* adressing modes (memory access direct) */

#define implied(ticks)				\
  tick(ticks);

#define immediate(ticks)			\
  tick(ticks);					\
  ea= PC++;

#define abs(ticks)				\
  tick(ticks);					\
  ea= memory[PC] + (memory[PC + 1] << 8);	\
  PC += 2;

#define relative(ticks)				\
  tick(ticks);					\
  ea= memory[PC++];				\
  if (ea & 0x80) ea -= 0x100;			\
  tickIf((ea >> 8) != (PC >> 8));

#define indirect(ticks)				\
  tick(ticks);					\
  {						\
    word tmp;					\
    tmp= memory[PC]  + (memory[PC  + 1] << 8);	\
    ea = memory[tmp] + (memory[tmp + 1] << 8);	\
    PC += 2;					\
  }

#define absx(ticks)						\
  tick(ticks);							\
  ea= memory[PC] + (memory[PC + 1] << 8);			\
  PC += 2;							\
  tickIf((ticks == 4) && ((ea >> 8) != ((ea + X) >> 8)));	\
  ea += X;

#define absy(ticks)						\
  tick(ticks);							\
  ea= memory[PC] + (memory[PC + 1] << 8);			\
  PC += 2;							\
  tickIf((ticks == 4) && ((ea >> 8) != ((ea + Y) >> 8)));	\
  ea += Y

#define zp(ticks)				\
  tick(ticks);					\
  ea= memory[PC++];

#define zpx(ticks)				\
  tick(ticks);					\
  ea= memory[PC++] + X;				\
  ea &= 0x00ff;

#define zpy(ticks)				\
  tick(ticks);					\
  ea= memory[PC++] + Y;				\
  ea &= 0x00ff;

#define indx(ticks)				\
  tick(ticks);					\
  {						\
    byte tmp= memory[PC++] + X;			\
    ea= memory[tmp] + (memory[tmp + 1] << 8);	\
  }

#define indy(ticks)						\
  tick(ticks);							\
  {								\
    byte tmp= memory[PC++];					\
    ea= memory[tmp] + (memory[tmp + 1] << 8);			\
    tickIf((ticks == 5) && ((ea >> 8) != ((ea + Y) >> 8)));	\
    ea += Y;							\
  }

#define indabsx(ticks)					\
  tick(ticks);						\
  {							\
    word tmp;						\
    tmp= memory[PC ] + (memory[PC  + 1] << 8) + X;	\
    ea = memory[tmp] + (memory[tmp + 1] << 8);		\
  }

#define indzp(ticks)					\
  tick(ticks);						\
  {							\
    byte tmp;						\
    tmp= memory[PC++];					\
    ea = memory[tmp] + (memory[tmp + 1] << 8);		\
  }

/* insns */

#define adc(ticks, adrmode)								\
  adrmode(ticks);									\
  {											\
    byte B= getMemory(ea);								\
    if (!getD())									\
      {											\
	int c= A + B + getC();								\
	int v= (int8_t)A + (int8_t)B + getC();						\
	fetch();									\
	A= c;										\
	setNVZC((A & 0x80), (((A & 0x80) > 0) ^ (v < 0)), (A == 0), ((c & 0x100) > 0));	\
	next();										\
      }											\
    else										\
      {											\
	/* Algorithm taken from http://www.6502.org/tutorials/decimal_mode.html */      \
	/* inelegant & slow, but consistent with the hw for illegal digits */		\
	int l, s, t, v;									\
	l= (A & 0x0F) + (B & 0x0F) + getC();						\
	if (l >= 0x0A) { l = ((l + 0x06) & 0x0F) + 0x10; }				\
	s= (A & 0xF0) + (B & 0xF0) + l;							\
	t= (int8_t)(A & 0xF0) + (int8_t)(B & 0xF0) + (int8_t)l;				\
	v= (t < -128) || (t > 127);							\
	if (s >= 0xA0) { s += 0x60; }							\
        fetch();									\
	A= s;										\
	/* only C is valid on NMOS 6502 */						\
	setNVZC(s & 0x80, v, !A, (s >= 0x100));						\
	tick(1);									\
	next();										\
      }											\
  }

#define sbc(ticks, adrmode)								\
  adrmode(ticks);									\
  {											\
    byte B= getMemory(ea);								\
    if (!getD())									\
      {											\
	int b= 1 - (P &0x01);								\
	int c= A - B - b;								\
	int v= (int8_t)A - (int8_t) B - b;						\
	fetch();									\
	A= c;										\
	setNVZC(A & 0x80, ((A & 0x80) > 0) ^ ((v & 0x100) != 0), A == 0, c >= 0);	\
	next();										\
      }											\
    else										\
      {											\
	/* Algorithm taken from http://www.6502.org/tutorials/decimal_mode.html */      \
	int b= 1 - (P &0x01);								\
	int l= (A & 0x0F) - (B & 0x0F) - b;	 					\
	int s= A - B + getC() - 1;							\
	int c= !(s & 0x100);								\
	int v= (int8_t)A - (int8_t) B - b;						\
      	if (s < 0) { s -= 0x60; } 							\
	if (l < 0) { s -= 0x06; }							\
	fetch();									\
	A = s;										\
	/* only C is valid on NMOS 6502 */						\
	setNVZC(s & 0x80, ((v & 0x80) > 0) ^ ((v & 0x100) != 0), !A, c);		\
	tick(1);									\
	next();										\
      }											\
  }

#define cmpR(ticks, adrmode, R)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte B= getMemory(ea);			\
    byte d= R - B;				\
    setNZC(d & 0x80, !d, R >= B);		\
  }						\
  next();

#define cmp(ticks, adrmode)	cmpR(ticks, adrmode, A)
#define cpx(ticks, adrmode)	cmpR(ticks, adrmode, X)
#define cpy(ticks, adrmode)	cmpR(ticks, adrmode, Y)

#define dec(ticks, adrmode)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte B= getMemory(ea);			\
    --B;					\
    putMemory(ea, B);				\
    setNZ(B & 0x80, !B);			\
  }						\
  next();

#define decR(ticks, adrmode, R)			\
  fetch();					\
  tick(ticks);					\
  --R;						\
  setNZ(R & 0x80, !R);				\
  next();

#define dea(ticks, adrmode)	decR(ticks, adrmode, A)
#define dex(ticks, adrmode)	decR(ticks, adrmode, X)
#define dey(ticks, adrmode)	decR(ticks, adrmode, Y)

#define inc(ticks, adrmode)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte B= getMemory(ea);			\
    ++B;					\
    putMemory(ea, B);				\
    setNZ(B & 0x80, !B);			\
  }						\
  next();

#define incR(ticks, adrmode, R)			\
  fetch();					\
  tick(ticks);					\
  ++R;						\
  setNZ(R & 0x80, !R);				\
  next();

#define ina(ticks, adrmode)	incR(ticks, adrmode, A)
#define inx(ticks, adrmode)	incR(ticks, adrmode, X)
#define iny(ticks, adrmode)	incR(ticks, adrmode, Y)

#define bit(ticks, adrmode)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte B= getMemory(ea);			\
    P= (P & ~(flagN | flagV | flagZ))		\
      | (B & (0xC0)) | (((A & B) == 0) << 1);	\
  }						\
  next();

/* BIT is unique in varying its behaviour based on addressing mode;
 * BIT immediate only modifies the Z flag.
 * http://6502.org/tutorials/65c02opcodes.html
 */
#define bim(ticks, adrmode)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte B= getMemory(ea);			\
    setZ((A & B) == 0);                  	\
  }						\
  next();

#define tsb(ticks, adrmode)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte b= getMemory(ea);			\
    setZ(!(b & A));				\
    b |= A;					\
    putMemory(ea, b);				\
  }						\
  next();

#define trb(ticks, adrmode)			\
  adrmode(ticks);				\
  fetch();					\
  {						\
    byte b= getMemory(ea);			\
    setZ(!(b & A));				\
    b &= (A ^ 0xFF);				\
    putMemory(ea, b);				\
  }						\
  next();

#define bitwise(ticks, adrmode, op)		\
  adrmode(ticks);				\
  fetch();					\
  A op##= getMemory(ea);			\
  setNZ(A & 0x80, !A);				\
  next();

#define and(ticks, adrmode)	bitwise(ticks, adrmode, &)
#define eor(ticks, adrmode)	bitwise(ticks, adrmode, ^)
#define ora(ticks, adrmode)	bitwise(ticks, adrmode, |)

#define asl(ticks, adrmode)			\
  adrmode(ticks);				\
  {						\
    unsigned int i= getMemory(ea) << 1;		\
    putMemory(ea, i);				\
    fetch();					\
    setNZC(i & 0x80, !i, i >> 8);		\
  }						\
  next();

#define asla(ticks, adrmode)			\
  tick(ticks);					\
  fetch();					\
  {						\
    int c= A >> 7;				\
    A <<= 1;					\
    setNZC(A & 0x80, !A, c);			\
  }						\
  next();

#define lsr(ticks, adrmode)			\
  adrmode(ticks);				\
  {						\
    byte b= getMemory(ea);			\
    int  c= b & 1;				\
    fetch();					\
    b >>= 1;					\
    putMemory(ea, b);				\
    setNZC(0, !b, c);				\
  }						\
  next();

#define lsra(ticks, adrmode)			\
  tick(ticks);					\
  fetch();					\
  {						\
    int c= A & 1;				\
    A >>= 1;					\
    setNZC(0, !A, c);				\
  }						\
  next();

#define rol(ticks, adrmode)			\
  adrmode(ticks);				\
  {						\
    word b= (getMemory(ea) << 1) | getC();	\
    fetch();					\
    putMemory(ea, b);				\
    setNZC(b & 0x80, !(b & 0xFF), b >> 8);	\
  }						\
  next();

#define rola(ticks, adrmode)			\
  tick(ticks);					\
  fetch();					\
  {						\
    word b= (A << 1) | getC();			\
    A= b;					\
    setNZC(A & 0x80, !A, b >> 8);		\
  }						\
  next();

#define ror(ticks, adrmode)			\
  adrmode(ticks);				\
  {						\
    int  c= getC();				\
    byte m= getMemory(ea);			\
    byte b= (c << 7) | (m >> 1);		\
    fetch();					\
    putMemory(ea, b);				\
    setNZC(b & 0x80, !b, m & 1);		\
  }						\
  next();

#define rora(ticks, adrmode)			\
  adrmode(ticks);				\
  {						\
    int ci= getC();				\
    int co= A & 1;				\
    fetch();					\
    A= (ci << 7) | (A >> 1);			\
    setNZC(A & 0x80, !A, co);			\
  }						\
  next();

#define tRS(ticks, adrmode, R, S)		\
  fetch();					\
  tick(ticks);					\
  S= R;						\
  setNZ(S & 0x80, !S);				\
  next();

#define tax(ticks, adrmode)	tRS(ticks, adrmode, A, X)
#define txa(ticks, adrmode)	tRS(ticks, adrmode, X, A)
#define tay(ticks, adrmode)	tRS(ticks, adrmode, A, Y)
#define tya(ticks, adrmode)	tRS(ticks, adrmode, Y, A)
#define tsx(ticks, adrmode)	tRS(ticks, adrmode, S, X)

#define txs(ticks, adrmode)			\
  fetch();					\
  tick(ticks);					\
  S= X;						\
  next();

#define ldR(ticks, adrmode, R)			\
  adrmode(ticks);				\
  fetch();					\
  R= getMemory(ea);				\
  setNZ(R & 0x80, !R);				\
  next();

#define lda(ticks, adrmode)	ldR(ticks, adrmode, A)
#define ldx(ticks, adrmode)	ldR(ticks, adrmode, X)
#define ldy(ticks, adrmode)	ldR(ticks, adrmode, Y)

#define stR(ticks, adrmode, R)			\
  adrmode(ticks);				\
  fetch();					\
  putMemory(ea, R);				\
  next();

#define sta(ticks, adrmode)	stR(ticks, adrmode, A)
#define stx(ticks, adrmode)	stR(ticks, adrmode, X)
#define sty(ticks, adrmode)	stR(ticks, adrmode, Y)
#define stz(ticks, adrmode)	stR(ticks, adrmode, 0)

#define branch(ticks, adrmode, cond)		\
  if (cond)					\
    {						\
      adrmode(ticks);				\
      PC += ea;					\
      tick(1);					\
    }						\
  else						\
    {						\
      tick(ticks);				\
      PC++;					\
    }						\
  fetch();					\
  next();

#define bcc(ticks, adrmode)	branch(ticks, adrmode, !getC())
#define bcs(ticks, adrmode)	branch(ticks, adrmode,  getC())
#define bne(ticks, adrmode)	branch(ticks, adrmode, !getZ())
#define beq(ticks, adrmode)	branch(ticks, adrmode,  getZ())
#define bpl(ticks, adrmode)	branch(ticks, adrmode, !getN())
#define bmi(ticks, adrmode)	branch(ticks, adrmode,  getN())
#define bvc(ticks, adrmode)	branch(ticks, adrmode, !getV())
#define bvs(ticks, adrmode)	branch(ticks, adrmode,  getV())

#define bra(ticks, adrmode)			\
  adrmode(ticks);				\
  PC += ea;					\
  fetch();					\
  tick(1);					\
  next();

#define jmp(ticks, adrmode)					\
  {								\
      adrmode(ticks);						\
      byte opcode= mpu->memory[PC-3];                          	\
      PC= ea;							\
      if (mpu->callbacks->call[ea])				\
	{							\
	  word addr;						\
	  externalise();					\
	  if ((addr= mpu->callbacks->call[ea](mpu, ea, opcode)))\
	    {							\
	      internalise();					\
	      PC= addr;						\
	    }							\
	}							\
      fetch();							\
      next();							\
  }

#define jsr(ticks, adrmode)				\
  PC++;							\
  push(PC >> 8);					\
  push(PC & 0xff);					\
  PC--;							\
  adrmode(ticks);					\
  if (mpu->callbacks->call[ea])				\
    {							\
      word addr;					\
      externalise();					\
      if ((addr= mpu->callbacks->call[ea](mpu, ea, 0x20))) \
	{						\
	  internalise();				\
	  PC= addr;					\
	  fetch();					\
	  next();					\
	}						\
    }							\
  PC=ea;						\
  fetch();						\
  next();

#define rts(ticks, adrmode)			\
  tick(ticks);					\
  PC  =  pop();					\
  PC |= (pop() << 8);				\
  PC++;						\
  fetch();					\
  next();

#define brk(ticks, adrmode)					\
  tick(ticks);							\
  PC++;								\
  push(PC >> 8);						\
  push(PC & 0xff);						\
  P |= flagB;							\
  /* http://www.6502.org/tutorials/65c02opcodes.html - unlike
   * the 6502, the 65C02 clears D on BRK.
   */								\
  P &= ~flagD;                                                  \
  push(P | flagX);						\
  P |= flagI;							\
  {								\
    word hdlr= getMemory(0xfffe) + (getMemory(0xffff) << 8);	\
    if (mpu->callbacks->call[hdlr])				\
      {								\
	word addr;						\
	externalise();						\
	if ((addr= mpu->callbacks->call[hdlr](mpu, PC - 2, 0)))	\
	  {							\
	    internalise();					\
	    hdlr= addr;						\
	  }							\
      }								\
    PC= hdlr;							\
  }								\
  fetch();							\
  next();

#define rti(ticks, adrmode)			\
  tick(ticks);					\
  P=     pop();					\
  PC=    pop();					\
  PC |= (pop() << 8);				\
  fetch();					\
  next();

#define nop(ticks, adrmode)			\
  fetch();					\
  tick(ticks);					\
  next();

/* determine addr and instruction before calling fetch(), otherwise the GNU C version gets it wrong */
#define ill(ticks, adrmode)								\
  {											\
    word addr= PC-1;									\
    byte instruction= memory[addr];							\
    tick(ticks);									\
    if (mpu->callbacks->illegal_instruction[instruction])				\
      {											\
	adrmode(ticks);									\
	externalise();									\
        if (addr= (mpu->callbacks->illegal_instruction[instruction](mpu, addr,          \
								    instruction)))      \
          {										\
	    mpu->registers->pc= addr;							\
          }										\
	internalise();									\
        fetch();									\
	next();										\
      }											\
    else										\
      {											\
        adrmode(ticks);                                                                 \
        fetch();                                                                        \
        next();                                                                         \
      }											\
  };

#define phR(ticks, adrmode, R)			\
  fetch();					\
  tick(ticks);					\
  push(R);					\
  next();

#define pha(ticks, adrmode)	phR(ticks, adrmode, A)
#define phx(ticks, adrmode)	phR(ticks, adrmode, X)
#define phy(ticks, adrmode)	phR(ticks, adrmode, Y)
#define php(ticks, adrmode)	phR(ticks, adrmode, P | flagX | flagB)

#define plR(ticks, adrmode, R)			\
  fetch();					\
  tick(ticks);					\
  R= pop();					\
  setNZ(R & 0x80, !R);				\
  next();

#define pla(ticks, adrmode)	plR(ticks, adrmode, A)
#define plx(ticks, adrmode)	plR(ticks, adrmode, X)
#define ply(ticks, adrmode)	plR(ticks, adrmode, Y)

#define plp(ticks, adrmode)			\
  fetch();					\
  tick(ticks);					\
  P= pop();					\
  next();

#define clF(ticks, adrmode, F)			\
  fetch();					\
  tick(ticks);					\
  P &= ~F;					\
  next();

#define clc(ticks, adrmode)	clF(ticks, adrmode, flagC)
#define cld(ticks, adrmode)	clF(ticks, adrmode, flagD)
#define cli(ticks, adrmode)	clF(ticks, adrmode, flagI)
#define clv(ticks, adrmode)	clF(ticks, adrmode, flagV)

#define seF(ticks, adrmode, F)			\
  fetch();					\
  tick(ticks);					\
  P |= F;					\
  next();

#define sec(ticks, adrmode)	seF(ticks, adrmode, flagC)
#define sed(ticks, adrmode)	seF(ticks, adrmode, flagD)
#define sei(ticks, adrmode)	seF(ticks, adrmode, flagI)

#define do_insns(_)												\
  _(00, brk, implied,   7);  _(01, ora, indx,      6);  _(02, ill, implied,   2);  _(03, ill, implied, 2);      \
  _(04, tsb, zp,        3);  _(05, ora, zp,        3);  _(06, asl, zp,        5);  _(07, ill, implied, 2);      \
  _(08, php, implied,   3);  _(09, ora, immediate, 3);  _(0a, asla,implied,   2);  _(0b, ill, implied, 2);      \
  _(0c, tsb, abs,       4);  _(0d, ora, abs,       4);  _(0e, asl, abs,       6);  _(0f, ill, implied, 2);      \
  _(10, bpl, relative,  2);  _(11, ora, indy,      5);  _(12, ora, indzp,     3);  _(13, ill, implied, 2);      \
  _(14, trb, zp,        3);  _(15, ora, zpx,       4);  _(16, asl, zpx,       6);  _(17, ill, implied, 2);      \
  _(18, clc, implied,   2);  _(19, ora, absy,      4);  _(1a, ina, implied,   2);  _(1b, ill, implied, 2);      \
  _(1c, trb, abs,       4);  _(1d, ora, absx,      4);  _(1e, asl, absx,      7);  _(1f, ill, implied, 2);      \
  _(20, jsr, abs,       6);  _(21, and, indx,      6);  _(22, ill, implied,   2);  _(23, ill, implied, 2);      \
  _(24, bit, zp,        3);  _(25, and, zp,        3);  _(26, rol, zp,        5);  _(27, ill, implied, 2);      \
  _(28, plp, implied,   4);  _(29, and, immediate, 3);  _(2a, rola,implied,   2);  _(2b, ill, implied, 2);      \
  _(2c, bit, abs,       4);  _(2d, and, abs,       4);  _(2e, rol, abs,       6);  _(2f, ill, implied, 2);      \
  _(30, bmi, relative,  2);  _(31, and, indy,      5);  _(32, and, indzp,     3);  _(33, ill, implied, 2);      \
  _(34, bit, zpx,       4);  _(35, and, zpx,       4);  _(36, rol, zpx,       6);  _(37, ill, implied, 2);      \
  _(38, sec, implied,   2);  _(39, and, absy,      4);  _(3a, dea, implied,   2);  _(3b, ill, implied, 2);      \
  _(3c, bit, absx,      4);  _(3d, and, absx,      4);  _(3e, rol, absx,      7);  _(3f, ill, implied, 2);      \
  _(40, rti, implied,   6);  _(41, eor, indx,      6);  _(42, ill, implied,   2);  _(43, ill, implied, 2);      \
  _(44, ill, zp,        3);  _(45, eor, zp,        3);  _(46, lsr, zp,        5);  _(47, ill, implied, 2);      \
  _(48, pha, implied,   3);  _(49, eor, immediate, 3);  _(4a, lsra,implied,   2);  _(4b, ill, implied, 2);      \
  _(4c, jmp, abs,       3);  _(4d, eor, abs,       4);  _(4e, lsr, abs,       6);  _(4f, ill, implied, 2);      \
  _(50, bvc, relative,  2);  _(51, eor, indy,      5);  _(52, eor, indzp,     3);  _(53, ill, implied, 2);      \
  _(54, ill, zp,        4);  _(55, eor, zpx,       4);  _(56, lsr, zpx,       6);  _(57, ill, implied, 2);      \
  _(58, cli, implied,   2);  _(59, eor, absy,      4);  _(5a, phy, implied,   3);  _(5b, ill, implied, 2);      \
  _(5c, ill, abs,       8);  _(5d, eor, absx,      4);  _(5e, lsr, absx,      7);  _(5f, ill, implied, 2);      \
  _(60, rts, implied,   6);  _(61, adc, indx,      6);  _(62, ill, implied,   2);  _(63, ill, implied, 2);      \
  _(64, stz, zp,        3);  _(65, adc, zp,        3);  _(66, ror, zp,        5);  _(67, ill, implied, 2);      \
  _(68, pla, implied,   4);  _(69, adc, immediate, 3);  _(6a, rora,implied,   2);  _(6b, ill, implied, 2);      \
  _(6c, jmp, indirect,  5);  _(6d, adc, abs,       4);  _(6e, ror, abs,       6);  _(6f, ill, implied, 2);      \
  _(70, bvs, relative,  2);  _(71, adc, indy,      5);  _(72, adc, indzp,     3);  _(73, ill, implied, 2);      \
  _(74, stz, zpx,       4);  _(75, adc, zpx,       4);  _(76, ror, zpx,       6);  _(77, ill, implied, 2);      \
  _(78, sei, implied,   2);  _(79, adc, absy,      4);  _(7a, ply, implied,   4);  _(7b, ill, implied, 2);      \
  _(7c, jmp, indabsx,   6);  _(7d, adc, absx,      4);  _(7e, ror, absx,      7);  _(7f, ill, implied, 2);      \
  _(80, bra, relative,  2);  _(81, sta, indx,      6);  _(82, ill, implied,   2);  _(83, ill, implied, 2);      \
  _(84, sty, zp,        2);  _(85, sta, zp,        2);  _(86, stx, zp,        2);  _(87, ill, implied, 2);      \
  _(88, dey, implied,   2);  _(89, bit, immediate, 2);  _(8a, txa, implied,   2);  _(8b, ill, implied, 2);      \
  _(8c, sty, abs,       4);  _(8d, sta, abs,       4);  _(8e, stx, abs,       4);  _(8f, ill, implied, 2);      \
  _(90, bcc, relative,  2);  _(91, sta, indy,      6);  _(92, sta, indzp,     3);  _(93, ill, implied, 2);      \
  _(94, sty, zpx,       4);  _(95, sta, zpx,       4);  _(96, stx, zpy,       4);  _(97, ill, implied, 2);      \
  _(98, tya, implied,   2);  _(99, sta, absy,      5);  _(9a, txs, implied,   2);  _(9b, ill, implied, 2);      \
  _(9c, stz, abs,       4);  _(9d, sta, absx,      5);  _(9e, stz, absx,      5);  _(9f, ill, implied, 2);      \
  _(a0, ldy, immediate, 3);  _(a1, lda, indx,      6);  _(a2, ldx, immediate, 3);  _(a3, ill, implied, 2);      \
  _(a4, ldy, zp,        3);  _(a5, lda, zp,        3);  _(a6, ldx, zp,        3);  _(a7, ill, implied, 2);      \
  _(a8, tay, implied,   2);  _(a9, lda, immediate, 3);  _(aa, tax, implied,   2);  _(ab, ill, implied, 2);      \
  _(ac, ldy, abs,       4);  _(ad, lda, abs,       4);  _(ae, ldx, abs,       4);  _(af, ill, implied, 2);      \
  _(b0, bcs, relative,  2);  _(b1, lda, indy,      5);  _(b2, lda, indzp,     3);  _(b3, ill, implied, 2);      \
  _(b4, ldy, zpx,       4);  _(b5, lda, zpx,       4);  _(b6, ldx, zpy,       4);  _(b7, ill, implied, 2);      \
  _(b8, clv, implied,   2);  _(b9, lda, absy,      4);  _(ba, tsx, implied,   2);  _(bb, ill, implied, 2);      \
  _(bc, ldy, absx,      4);  _(bd, lda, absx,      4);  _(be, ldx, absy,      4);  _(bf, ill, implied, 2);      \
  _(c0, cpy, immediate, 3);  _(c1, cmp, indx,      6);  _(c2, ill, implied,   2);  _(c3, ill, implied, 2);      \
  _(c4, cpy, zp,        3);  _(c5, cmp, zp,        3);  _(c6, dec, zp,        5);  _(c7, ill, implied, 2);      \
  _(c8, iny, implied,   2);  _(c9, cmp, immediate, 3);  _(ca, dex, implied,   2);  _(cb, ill, implied, 2);      \
  _(cc, cpy, abs,       4);  _(cd, cmp, abs,       4);  _(ce, dec, abs,       6);  _(cf, ill, implied, 2);      \
  _(d0, bne, relative,  2);  _(d1, cmp, indy,      5);  _(d2, cmp, indzp,     3);  _(d3, ill, implied, 2);      \
  _(d4, ill, zp,        4);  _(d5, cmp, zpx,       4);  _(d6, dec, zpx,       6);  _(d7, ill, implied, 2);      \
  _(d8, cld, implied,   2);  _(d9, cmp, absy,      4);  _(da, phx, implied,   3);  _(db, ill, implied, 2);      \
  _(dc, ill, abs,       4);  _(dd, cmp, absx,      4);  _(de, dec, absx,      7);  _(df, ill, implied, 2);      \
  _(e0, cpx, immediate, 3);  _(e1, sbc, indx,      6);  _(e2, ill, implied,   2);  _(e3, ill, implied, 2);      \
  _(e4, cpx, zp,        3);  _(e5, sbc, zp,        3);  _(e6, inc, zp,        5);  _(e7, ill, implied, 2);      \
  _(e8, inx, implied,   2);  _(e9, sbc, immediate, 3);  _(ea, nop, implied,   2);  _(eb, ill, implied, 2);      \
  _(ec, cpx, abs,       4);  _(ed, sbc, abs,       4);  _(ee, inc, abs,       6);  _(ef, ill, implied, 2);      \
  _(f0, beq, relative,  2);  _(f1, sbc, indy,      5);  _(f2, sbc, indzp,     3);  _(f3, ill, implied, 2);      \
  _(f4, ill, zp,        4);  _(f5, sbc, zpx,       4);  _(f6, inc, zpx,       6);  _(f7, ill, implied, 2);      \
  _(f8, sed, implied,   2);  _(f9, sbc, absy,      4);  _(fa, plx, implied,   4);  _(fb, ill, implied, 2);      \
  _(fc, ill, abs,       4);  _(fd, sbc, absx,      4);  _(fe, inc, absx,      7);  _(ff, ill, implied, 2);



void M6502_irq(M6502 *mpu)
{
  if (!(mpu->registers->p & flagI))
    {
      mpu->memory[0x0100 + mpu->registers->s--] = (byte)(mpu->registers->pc >> 8);
      mpu->memory[0x0100 + mpu->registers->s--] = (byte)(mpu->registers->pc & 0xff);
      mpu->memory[0x0100 + mpu->registers->s--] = mpu->registers->p;
      mpu->registers->p &= ~flagB;
      mpu->registers->p |=  flagI;
      mpu->registers->pc = M6502_getVector(mpu, IRQ);
    }
}


void M6502_nmi(M6502 *mpu)
{
  mpu->memory[0x0100 + mpu->registers->s--] = (byte)(mpu->registers->pc >> 8);
  mpu->memory[0x0100 + mpu->registers->s--] = (byte)(mpu->registers->pc & 0xff);
  mpu->memory[0x0100 + mpu->registers->s--] = mpu->registers->p;
  mpu->registers->p &= ~flagB;
  mpu->registers->p |=  flagI;
  mpu->registers->pc = M6502_getVector(mpu, NMI);
}


void M6502_reset(M6502 *mpu)
{
  mpu->registers->p &= ~flagD;
  mpu->registers->p |=  flagI;
  mpu->registers->pc = M6502_getVector(mpu, RST);
}


/* the compiler should elminate all call to this function */

static void oops(void)
{
  fprintf(stderr, "\noops -- instruction dispatch missing\n");
}


void M6502_run(M6502 *mpu)
{
#if defined(__GNUC__) && !defined(__STRICT_ANSI__)

  static void *itab[256]= { &&_00, &&_01, &&_02, &&_03, &&_04, &&_05, &&_06, &&_07, &&_08, &&_09, &&_0a, &&_0b, &&_0c, &&_0d, &&_0e, &&_0f,
			    &&_10, &&_11, &&_12, &&_13, &&_14, &&_15, &&_16, &&_17, &&_18, &&_19, &&_1a, &&_1b, &&_1c, &&_1d, &&_1e, &&_1f,
			    &&_20, &&_21, &&_22, &&_23, &&_24, &&_25, &&_26, &&_27, &&_28, &&_29, &&_2a, &&_2b, &&_2c, &&_2d, &&_2e, &&_2f,
			    &&_30, &&_31, &&_32, &&_33, &&_34, &&_35, &&_36, &&_37, &&_38, &&_39, &&_3a, &&_3b, &&_3c, &&_3d, &&_3e, &&_3f,
			    &&_40, &&_41, &&_42, &&_43, &&_44, &&_45, &&_46, &&_47, &&_48, &&_49, &&_4a, &&_4b, &&_4c, &&_4d, &&_4e, &&_4f,
			    &&_50, &&_51, &&_52, &&_53, &&_54, &&_55, &&_56, &&_57, &&_58, &&_59, &&_5a, &&_5b, &&_5c, &&_5d, &&_5e, &&_5f,
			    &&_60, &&_61, &&_62, &&_63, &&_64, &&_65, &&_66, &&_67, &&_68, &&_69, &&_6a, &&_6b, &&_6c, &&_6d, &&_6e, &&_6f,
			    &&_70, &&_71, &&_72, &&_73, &&_74, &&_75, &&_76, &&_77, &&_78, &&_79, &&_7a, &&_7b, &&_7c, &&_7d, &&_7e, &&_7f,
			    &&_80, &&_81, &&_82, &&_83, &&_84, &&_85, &&_86, &&_87, &&_88, &&_89, &&_8a, &&_8b, &&_8c, &&_8d, &&_8e, &&_8f,
			    &&_90, &&_91, &&_92, &&_93, &&_94, &&_95, &&_96, &&_97, &&_98, &&_99, &&_9a, &&_9b, &&_9c, &&_9d, &&_9e, &&_9f,
			    &&_a0, &&_a1, &&_a2, &&_a3, &&_a4, &&_a5, &&_a6, &&_a7, &&_a8, &&_a9, &&_aa, &&_ab, &&_ac, &&_ad, &&_ae, &&_af,
			    &&_b0, &&_b1, &&_b2, &&_b3, &&_b4, &&_b5, &&_b6, &&_b7, &&_b8, &&_b9, &&_ba, &&_bb, &&_bc, &&_bd, &&_be, &&_bf,
			    &&_c0, &&_c1, &&_c2, &&_c3, &&_c4, &&_c5, &&_c6, &&_c7, &&_c8, &&_c9, &&_ca, &&_cb, &&_cc, &&_cd, &&_ce, &&_cf,
			    &&_d0, &&_d1, &&_d2, &&_d3, &&_d4, &&_d5, &&_d6, &&_d7, &&_d8, &&_d9, &&_da, &&_db, &&_dc, &&_dd, &&_de, &&_df,
			    &&_e0, &&_e1, &&_e2, &&_e3, &&_e4, &&_e5, &&_e6, &&_e7, &&_e8, &&_e9, &&_ea, &&_eb, &&_ec, &&_ed, &&_ee, &&_ef,
			    &&_f0, &&_f1, &&_f2, &&_f3, &&_f4, &&_f5, &&_f6, &&_f7, &&_f8, &&_f9, &&_fa, &&_fb, &&_fc, &&_fd, &&_fe, &&_ff };

  register void **itabp= &itab[0];
  register void  *tpc;

# define begin()				fetch();  next()
# define fetch()				tpc= itabp[memory[PC++]]
/* sf temp # define fetch()				do { tpc= itabp[memory[PC++]]; fprintf(stderr, "todo: %04X %02X\n", (unsigned) (PC-1), (unsigned) memory[PC-1]); } while(0) */
# define next()					goto *tpc
# define dispatch(num, name, mode, cycles)	_##num: name(cycles, mode) oops();  next()
# define end()

#else /* (!__GNUC__) || (__STRICT_ANSI__) */

# define begin()				for (;;) switch (memory[PC++]) {
# define fetch()
# define next()					break
# define dispatch(num, name, mode, cycles)	case 0x##num: name(cycles, mode);  next()
# define end()					}

#endif

  register byte  *memory= mpu->memory;
  register word   PC;
  word		  ea;
  byte		  A, X, Y, P, S;
  M6502_Callback *readCallback=  mpu->callbacks->read;
  M6502_Callback *writeCallback= mpu->callbacks->write;

# define internalise()	A= mpu->registers->a;  X= mpu->registers->x;  Y= mpu->registers->y;  P= mpu->registers->p;  S= mpu->registers->s;  PC= mpu->registers->pc
# define externalise()	mpu->registers->a= A;  mpu->registers->x= X;  mpu->registers->y= Y;  mpu->registers->p= P;  mpu->registers->s= S;  mpu->registers->pc= PC

  internalise();

  begin();
  do_insns(dispatch);
  end();

  externalise();
# undef begin
# undef internalise
# undef externalise
# undef fetch
# undef next
# undef dispatch
# undef end

}


int M6502_disassemble(M6502 *mpu, word ip, char buffer[64])
{
  char *s= buffer;
  byte *b= mpu->memory + ip;

  switch (b[0])
    {
#    define _implied							    return 1;
#    define _immediate	sprintf(s, "#%02X",	   b[1]);		    return 2;
#    define _zp		sprintf(s, "%02X",	   b[1]);		    return 2;
#    define _zpx	sprintf(s, "%02X,X",	   b[1]);		    return 2;
#    define _zpy	sprintf(s, "%02X,Y",	   b[1]);		    return 2;
#    define _abs	sprintf(s, "%02X%02X",	   b[2], b[1]);		    return 3;
#    define _absx	sprintf(s, "%02X%02X,X",   b[2], b[1]);		    return 3;
#    define _absy	sprintf(s, "%02X%02X,Y",   b[2], b[1]);		    return 3;
#    define _relative	sprintf(s, "%04X",	   ip + 2 + (int8_t)b[1]);  return 2;
#    define _indirect	sprintf(s, "(%02X%02X)",   b[2], b[1]);		    return 3;
#    define _indzp	sprintf(s, "(%02X)",	   b[1]);		    return 2;
#    define _indx	sprintf(s, "(%02X,X)",	   b[1]);		    return 2;
#    define _indy	sprintf(s, "(%02X),Y",	   b[1]);		    return 2;
#    define _indabsx	sprintf(s, "(%02X%02X,X)", b[2], b[1]);		    return 3;

#    define disassemble(num, name, mode, cycles) case 0x##num: s += sprintf(s, "%s ", #name); _##mode
      do_insns(disassemble);
#    undef _do
    }

  return 0;
}


void M6502_dump(M6502 *mpu, char buffer[64])
{
  M6502_Registers *r= mpu->registers;
  uint8_t p= r->p;
# define P(N,C) (p & (1 << (N)) ? (C) : '-')
  sprintf(buffer, "PC=%04X SP=%04X A=%02X X=%02X Y=%02X P=%02X %c%c%c%c%c%c%c%c",
	  r->pc, 0x0100 + r->s,
	  r->a, r->x, r->y, r->p,
	  P(7,'N'), P(6,'V'), P(5,'?'), P(4,'B'), P(3,'D'), P(2,'I'), P(1,'Z'), P(0,'C'));
# undef P
}


static void outOfMemory(void)
{
  fflush(stdout);
  fprintf(stderr, "\nout of memory\n");
  abort();
}


M6502 *M6502_new(M6502_Registers *registers, M6502_Memory memory, M6502_Callbacks *callbacks)
{
  M6502 *mpu= calloc(1, sizeof(M6502));
  if (!mpu) outOfMemory();

  if (!registers)  { registers = (M6502_Registers *)calloc(1, sizeof(M6502_Registers));  mpu->flags |= M6502_RegistersAllocated; }
  if (!memory   )  { memory    = (uint8_t         *)calloc(1, sizeof(M6502_Memory   ));  mpu->flags |= M6502_MemoryAllocated;    }
  if (!callbacks)  { callbacks = (M6502_Callbacks *)calloc(1, sizeof(M6502_Callbacks));  mpu->flags |= M6502_CallbacksAllocated; }

  if (!registers || !memory || !callbacks) outOfMemory();

  mpu->registers = registers;
  mpu->memory    = memory;
  mpu->callbacks = callbacks;

  return mpu;
}


void M6502_delete(M6502 *mpu)
{
  if (mpu->flags & M6502_CallbacksAllocated) free(mpu->callbacks);
  if (mpu->flags & M6502_MemoryAllocated   ) free(mpu->memory);
  if (mpu->flags & M6502_RegistersAllocated) free(mpu->registers);

  free(mpu);
}
