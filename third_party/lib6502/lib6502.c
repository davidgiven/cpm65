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
 *   - architectural variations (unimplemented/extended instructions) not
 * implemented
 *   - ANSI versions (from from gcc extensions) of the dispatch macros are
 * missing
 *   - emulator+disassembler in same object file (library is kind of pointless)
 */

#include <stdio.h>
#include <stdlib.h>

#include "lib6502.h"

typedef uint8_t byte;
typedef uint16_t word;

enum
{
    flagN = (1 << 7), /* negative 	 */
    flagV = (1 << 6), /* overflow 	 */
    flagX = (1 << 5), /* unused   	 */
    flagB = (1 << 4), /* irq from brk  */
    flagD = (1 << 3), /* decimal mode  */
    flagI = (1 << 2), /* irq disable   */
    flagZ = (1 << 1), /* zero          */
    flagC = (1 << 0)  /* carry         */
};

#define getN() (P & flagN)
#define getV() (P & flagV)
#define getB() (P & flagB)
#define getD() (P & flagD)
#define getI() (P & flagI)
#define getZ() (P & flagZ)
#define getC() (P & flagC)

#define setNVZC(N, V, Z, C)                                          \
    (P = (P & ~(flagN | flagV | flagZ | flagC)) | (N) | ((V) << 6) | \
         ((Z) << 1) | (C))
#define setNZC(N, Z, C) \
    (P = (P & ~(flagN | flagZ | flagC)) | (N) | ((Z) << 1) | (C))
#define setNZ(N, Z) (P = (P & ~(flagN | flagZ)) | (N) | ((Z) << 1))
#define setZ(Z) (P = (P & ~(flagZ)) | ((Z) << 1))
#define setC(C) (P = (P & ~(flagC)) | (C))

#define NAND(P, Q) (!((P) & (Q)))

#define tick(n)
#define tickIf(p)

/* memory access (indirect if callback installed) -- ARGUMENTS ARE EVALUATED
 * MORE THAN ONCE! */

#define putMemory(ADDR, BYTE)                                   \
    (writeCallback[ADDR] ? writeCallback[ADDR](mpu, ADDR, BYTE) \
                         : (memory[ADDR] = BYTE))

#define getMemory(ADDR) \
    (readCallback[ADDR] ? readCallback[ADDR](mpu, ADDR, 0) : memory[ADDR])

/* stack access (always direct) */

#define push(BYTE) (memory[0x0100 + S--] = (BYTE))
#define pop() (memory[++S + 0x0100])

/* adressing modes (memory access direct) */

#define implied(ticks) tick(ticks);

#define immediate(ticks) \
    tick(ticks);         \
    ea = PC++;

#define abs(ticks)                           \
    tick(ticks);                             \
    ea = memory[PC] + (memory[PC + 1] << 8); \
    PC += 2;

#define relative(ticks) \
    tick(ticks);        \
    ea = memory[PC++];  \
    if (ea & 0x80)      \
        ea -= 0x100;    \
    tickIf((ea >> 8) != (PC >> 8));

#define zpr(ticks)              \
  tick(ticks);                  \
  ea= memory[PC++];             \
  if (ea & 0x80) ea -= 0x100;   \
  tickIf((ea >> 8) != (PC >> 8));

#define indirect(ticks)                            \
    tick(ticks);                                   \
    {                                              \
        word tmp;                                  \
        tmp = memory[PC] + (memory[PC + 1] << 8);  \
        ea = memory[tmp] + (memory[tmp + 1] << 8); \
        PC += 2;                                   \
    }

#define absx(ticks)                                         \
    tick(ticks);                                            \
    ea = memory[PC] + (memory[PC + 1] << 8);                \
    PC += 2;                                                \
    tickIf((ticks == 4) && ((ea >> 8) != ((ea + X) >> 8))); \
    ea += X;

#define absy(ticks)                                         \
    tick(ticks);                                            \
    ea = memory[PC] + (memory[PC + 1] << 8);                \
    PC += 2;                                                \
    tickIf((ticks == 4) && ((ea >> 8) != ((ea + Y) >> 8))); \
    ea += Y

#define zp(ticks) \
    tick(ticks);  \
    ea = memory[PC++];

#define zpx(ticks)         \
    tick(ticks);           \
    ea = memory[PC++] + X; \
    ea &= 0x00ff;

#define zpy(ticks)         \
    tick(ticks);           \
    ea = memory[PC++] + Y; \
    ea &= 0x00ff;

#define indx(ticks)                                \
    tick(ticks);                                   \
    {                                              \
        byte tmp = memory[PC++] + X;               \
        ea = memory[tmp] + (memory[(tmp + 1) & 0xff] << 8); \
    }

#define indy(ticks)                                             \
    tick(ticks);                                                \
    {                                                           \
        byte tmp = memory[PC++];                                \
        ea = memory[tmp] + (memory[(tmp + 1) & 0xff] << 8);              \
        tickIf((ticks == 5) && ((ea >> 8) != ((ea + Y) >> 8))); \
        ea += Y;                                                \
    }

#define indabsx(ticks)                                \
    tick(ticks);                                      \
    {                                                 \
        word tmp;                                     \
        tmp = memory[PC] + (memory[PC + 1] << 8) + X; \
        ea = memory[tmp] + (memory[tmp + 1] << 8);    \
    }

#define indzp(ticks)                               \
    tick(ticks);                                   \
    {                                              \
        byte tmp;                                  \
        tmp = memory[PC++];                        \
        ea = memory[tmp] + (memory[(tmp + 1) & 0xff] << 8); \
    }

/* insns */

#define adc(ticks, adrmode)                                                    \
    adrmode(ticks);                                                            \
    {                                                                          \
        byte B = getMemory(ea);                                                \
        if (!getD())                                                           \
        {                                                                      \
            int c = A + B + getC();                                            \
            int v = (int8_t)A + (int8_t)B + getC();                            \
            fetch();                                                           \
            A = c;                                                             \
            setNVZC((A & 0x80),                                                \
                (((A & 0x80) > 0) ^ (v < 0)),                                  \
                (A == 0),                                                      \
                ((c & 0x100) > 0));                                            \
            next();                                                            \
        }                                                                      \
        else                                                                   \
        {                                                                      \
            /* Algorithm taken from                                            \
             * http://www.6502.org/tutorials/decimal_mode.html */              \
            /* inelegant & slow, but consistent with the hw for illegal digits \
             */                                                                \
            int l, s, t, v;                                                    \
            l = (A & 0x0F) + (B & 0x0F) + getC();                              \
            if (l >= 0x0A)                                                     \
            {                                                                  \
                l = ((l + 0x06) & 0x0F) + 0x10;                                \
            }                                                                  \
            s = (A & 0xF0) + (B & 0xF0) + l;                                   \
            t = (int8_t)(A & 0xF0) + (int8_t)(B & 0xF0) + (int8_t)l;           \
            v = (t < -128) || (t > 127);                                       \
            if (s >= 0xA0)                                                     \
            {                                                                  \
                s += 0x60;                                                     \
            }                                                                  \
            fetch();                                                           \
            A = s;                                                             \
            /* only C is valid on NMOS 6502 */                                 \
            setNVZC(s & 0x80, v, !A, (s >= 0x100));                            \
            tick(1);                                                           \
            next();                                                            \
        }                                                                      \
    }

#define sbc(ticks, adrmode)                                                  \
    adrmode(ticks);                                                          \
    {                                                                        \
        byte B = getMemory(ea);                                              \
        if (!getD())                                                         \
        {                                                                    \
            int b = 1 - (P & 0x01);                                          \
            int c = A - B - b;                                               \
            int v = (int8_t)A - (int8_t)B - b;                               \
            fetch();                                                         \
            A = c;                                                           \
            setNVZC(A & 0x80,                                                \
                ((A & 0x80) > 0) ^ ((v & 0x100) != 0),                       \
                A == 0,                                                      \
                c >= 0);                                                     \
            next();                                                          \
        }                                                                    \
        else                                                                 \
        {                                                                    \
            /* Algorithm taken from                                          \
             * http://www.6502.org/tutorials/decimal_mode.html */            \
            int b = 1 - (P & 0x01);                                          \
            int l = (A & 0x0F) - (B & 0x0F) - b;                             \
            int s = A - B + getC() - 1;                                      \
            int c = !(s & 0x100);                                            \
            int v = (int8_t)A - (int8_t)B - b;                               \
            if (s < 0)                                                       \
            {                                                                \
                s -= 0x60;                                                   \
            }                                                                \
            if (l < 0)                                                       \
            {                                                                \
                s -= 0x06;                                                   \
            }                                                                \
            fetch();                                                         \
            A = s;                                                           \
            /* only C is valid on NMOS 6502 */                               \
            setNVZC(s & 0x80, ((v & 0x80) > 0) ^ ((v & 0x100) != 0), !A, c); \
            tick(1);                                                         \
            next();                                                          \
        }                                                                    \
    }

#define cmpR(ticks, adrmode, R)       \
    adrmode(ticks);                   \
    fetch();                          \
    {                                 \
        byte B = getMemory(ea);       \
        byte d = R - B;               \
        setNZC(d & 0x80, !d, R >= B); \
    }                                 \
    next();

#define cmp(ticks, adrmode) cmpR(ticks, adrmode, A)
#define cpx(ticks, adrmode) cmpR(ticks, adrmode, X)
#define cpy(ticks, adrmode) cmpR(ticks, adrmode, Y)

#define dec(ticks, adrmode)     \
    adrmode(ticks);             \
    fetch();                    \
    {                           \
        byte B = getMemory(ea); \
        --B;                    \
        putMemory(ea, B);       \
        setNZ(B & 0x80, !B);    \
    }                           \
    next();

#define decR(ticks, adrmode, R) \
    fetch();                    \
    tick(ticks);                \
    --R;                        \
    setNZ(R & 0x80, !R);        \
    next();

#define dea(ticks, adrmode) decR(ticks, adrmode, A)
#define dex(ticks, adrmode) decR(ticks, adrmode, X)
#define dey(ticks, adrmode) decR(ticks, adrmode, Y)

#define inc(ticks, adrmode)     \
    adrmode(ticks);             \
    fetch();                    \
    {                           \
        byte B = getMemory(ea); \
        ++B;                    \
        putMemory(ea, B);       \
        setNZ(B & 0x80, !B);    \
    }                           \
    next();

#define incR(ticks, adrmode, R) \
    fetch();                    \
    tick(ticks);                \
    ++R;                        \
    setNZ(R & 0x80, !R);        \
    next();

#define ina(ticks, adrmode) incR(ticks, adrmode, A)
#define inx(ticks, adrmode) incR(ticks, adrmode, X)
#define iny(ticks, adrmode) incR(ticks, adrmode, Y)

#define bit(ticks, adrmode)                                 \
    adrmode(ticks);                                         \
    fetch();                                                \
    {                                                       \
        byte B = getMemory(ea);                             \
        P = (P & ~(flagN | flagV | flagZ)) | (B & (0xC0)) | \
            (((A & B) == 0) << 1);                          \
    }                                                       \
    next();

/* BIT is unique in varying its behaviour based on addressing mode;
 * BIT immediate only modifies the Z flag.
 * http://6502.org/tutorials/65c02opcodes.html
 */
#define bim(ticks, adrmode)     \
    adrmode(ticks);             \
    fetch();                    \
    {                           \
        byte B = getMemory(ea); \
        setZ((A & B) == 0);     \
    }                           \
    next();

#define tsb(ticks, adrmode)     \
    adrmode(ticks);             \
    fetch();                    \
    {                           \
        byte b = getMemory(ea); \
        setZ(!(b & A));         \
        b |= A;                 \
        putMemory(ea, b);       \
    }                           \
    next();

#define trb(ticks, adrmode)     \
    adrmode(ticks);             \
    fetch();                    \
    {                           \
        byte b = getMemory(ea); \
        setZ(!(b & A));         \
        b &= (A ^ 0xFF);        \
        putMemory(ea, b);       \
    }                           \
    next();

#define rmb0(ticks, adrmode) rmbN(ticks, adrmode, (1<<0))
#define rmb1(ticks, adrmode) rmbN(ticks, adrmode, (1<<1))
#define rmb2(ticks, adrmode) rmbN(ticks, adrmode, (1<<2))
#define rmb3(ticks, adrmode) rmbN(ticks, adrmode, (1<<3))
#define rmb4(ticks, adrmode) rmbN(ticks, adrmode, (1<<4))
#define rmb5(ticks, adrmode) rmbN(ticks, adrmode, (1<<5))
#define rmb6(ticks, adrmode) rmbN(ticks, adrmode, (1<<6))
#define rmb7(ticks, adrmode) rmbN(ticks, adrmode, (1<<7))

#define rmbN(ticks, adrmode, mask)  \
  adrmode(ticks);                   \
  fetch();                          \
  {                                 \
    byte b= getMemory(ea);          \
    b &= (byte)~mask;               \
    putMemory(ea, b);               \
  }                                 \
  next();

#define smb0(ticks, adrmode) smbN(ticks, adrmode, (1<<0))
#define smb1(ticks, adrmode) smbN(ticks, adrmode, (1<<1))
#define smb2(ticks, adrmode) smbN(ticks, adrmode, (1<<2))
#define smb3(ticks, adrmode) smbN(ticks, adrmode, (1<<3))
#define smb4(ticks, adrmode) smbN(ticks, adrmode, (1<<4))
#define smb5(ticks, adrmode) smbN(ticks, adrmode, (1<<5))
#define smb6(ticks, adrmode) smbN(ticks, adrmode, (1<<6))
#define smb7(ticks, adrmode) smbN(ticks, adrmode, (1<<7))

#define smbN(ticks, adrmode, mask)  \
  adrmode(ticks);                   \
  fetch();                          \
  {                                 \
    byte b= getMemory(ea);          \
    b |= mask;                      \
    putMemory(ea, b);               \
  }                                 \
  next();

#define bitwise(ticks, adrmode, op) \
    adrmode(ticks);                 \
    fetch();                        \
    A op## = getMemory(ea);         \
    setNZ(A & 0x80, !A);            \
    next();

#define and(ticks, adrmode) bitwise(ticks, adrmode, &)
#define eor(ticks, adrmode) bitwise(ticks, adrmode, ^)
#define ora(ticks, adrmode) bitwise(ticks, adrmode, |)

#define asl(ticks, adrmode)                  \
    adrmode(ticks);                          \
    {                                        \
        unsigned int i = getMemory(ea) << 1; \
        putMemory(ea, i);                    \
        fetch();                             \
        setNZC(i & 0x80, !(i & 0xff), i >> 8);        \
    }                                        \
    next();

#define asla(ticks, adrmode)     \
    tick(ticks);                 \
    fetch();                     \
    {                            \
        int c = A >> 7;          \
        A <<= 1;                 \
        setNZC(A & 0x80, !A, c); \
    }                            \
    next();

#define lsr(ticks, adrmode)     \
    adrmode(ticks);             \
    {                           \
        byte b = getMemory(ea); \
        int c = b & 1;          \
        fetch();                \
        b >>= 1;                \
        putMemory(ea, b);       \
        setNZC(0, !b, c);       \
    }                           \
    next();

#define lsra(ticks, adrmode) \
    tick(ticks);             \
    fetch();                 \
    {                        \
        int c = A & 1;       \
        A >>= 1;             \
        setNZC(0, !A, c);    \
    }                        \
    next();

#define rol(ticks, adrmode)                     \
    adrmode(ticks);                             \
    {                                           \
        word b = (getMemory(ea) << 1) | getC(); \
        fetch();                                \
        putMemory(ea, b);                       \
        setNZC(b & 0x80, !(b & 0xFF), b >> 8);  \
    }                                           \
    next();

#define rola(ticks, adrmode)          \
    tick(ticks);                      \
    fetch();                          \
    {                                 \
        word b = (A << 1) | getC();   \
        A = b;                        \
        setNZC(A & 0x80, !A, b >> 8); \
    }                                 \
    next();

#define ror(ticks, adrmode)           \
    adrmode(ticks);                   \
    {                                 \
        int c = getC();               \
        byte m = getMemory(ea);       \
        byte b = (c << 7) | (m >> 1); \
        fetch();                      \
        putMemory(ea, b);             \
        setNZC(b & 0x80, !b, m & 1);  \
    }                                 \
    next();

#define rora(ticks, adrmode)      \
    adrmode(ticks);               \
    {                             \
        int ci = getC();          \
        int co = A & 1;           \
        fetch();                  \
        A = (ci << 7) | (A >> 1); \
        setNZC(A & 0x80, !A, co); \
    }                             \
    next();

#define tRS(ticks, adrmode, R, S) \
    fetch();                      \
    tick(ticks);                  \
    S = R;                        \
    setNZ(S & 0x80, !S);          \
    next();

#define tax(ticks, adrmode) tRS(ticks, adrmode, A, X)
#define txa(ticks, adrmode) tRS(ticks, adrmode, X, A)
#define tay(ticks, adrmode) tRS(ticks, adrmode, A, Y)
#define tya(ticks, adrmode) tRS(ticks, adrmode, Y, A)
#define tsx(ticks, adrmode) tRS(ticks, adrmode, S, X)

#define txs(ticks, adrmode) \
    fetch();                \
    tick(ticks);            \
    S = X;                  \
    next();

#define ldR(ticks, adrmode, R) \
    adrmode(ticks);            \
    fetch();                   \
    R = getMemory(ea);         \
    setNZ(R & 0x80, !R);       \
    next();

#define lda(ticks, adrmode) ldR(ticks, adrmode, A)
#define ldx(ticks, adrmode) ldR(ticks, adrmode, X)
#define ldy(ticks, adrmode) ldR(ticks, adrmode, Y)

#define stR(ticks, adrmode, R) \
    adrmode(ticks);            \
    fetch();                   \
    putMemory(ea, R);          \
    next();

#define sta(ticks, adrmode) stR(ticks, adrmode, A)
#define stx(ticks, adrmode) stR(ticks, adrmode, X)
#define sty(ticks, adrmode) stR(ticks, adrmode, Y)
#define stz(ticks, adrmode) stR(ticks, adrmode, 0)

#define branch(ticks, adrmode, cond) \
    if (cond)                        \
    {                                \
        adrmode(ticks);              \
        PC += ea;                    \
        tick(1);                     \
    }                                \
    else                             \
    {                                \
        tick(ticks);                 \
        PC++;                        \
    }                                \
    fetch();                         \
    next();

#define bbr0(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<0)))
#define bbr1(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<1)))
#define bbr2(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<2)))
#define bbr3(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<3)))
#define bbr4(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<4)))
#define bbr5(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<5)))
#define bbr6(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<6)))
#define bbr7(ticks, adrmode)    branch(ticks, adrmode, !(memory[memory[PC++]] & (1<<7)))

#define bbs0(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<0)))
#define bbs1(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<1)))
#define bbs2(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<2)))
#define bbs3(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<3)))
#define bbs4(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<4)))
#define bbs5(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<5)))
#define bbs6(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<6)))
#define bbs7(ticks, adrmode)    branch(ticks, adrmode,  (memory[memory[PC++]] & (1<<7)))

#define bcc(ticks, adrmode) branch(ticks, adrmode, !getC())
#define bcs(ticks, adrmode) branch(ticks, adrmode, getC())
#define bne(ticks, adrmode) branch(ticks, adrmode, !getZ())
#define beq(ticks, adrmode) branch(ticks, adrmode, getZ())
#define bpl(ticks, adrmode) branch(ticks, adrmode, !getN())
#define bmi(ticks, adrmode) branch(ticks, adrmode, getN())
#define bvc(ticks, adrmode) branch(ticks, adrmode, !getV())
#define bvs(ticks, adrmode) branch(ticks, adrmode, getV())

#define bra(ticks, adrmode) \
    adrmode(ticks);         \
    PC += ea;               \
    fetch();                \
    tick(1);                \
    next();

#define jmp(ticks, adrmode)                                         \
    {                                                               \
        adrmode(ticks);                                             \
        byte opcode = mpu->memory[PC - 3];                          \
        PC = ea;                                                    \
        if (mpu->callbacks->call[ea])                               \
        {                                                           \
            word addr;                                              \
            externalise();                                          \
            if ((addr = mpu->callbacks->call[ea](mpu, ea, opcode))) \
            {                                                       \
                internalise();                                      \
                PC = addr;                                          \
            }                                                       \
        }                                                           \
        fetch();                                                    \
        next();                                                     \
    }

#define jsr(ticks, adrmode)                                   \
    PC++;                                                     \
    push(PC >> 8);                                            \
    push(PC & 0xff);                                          \
    PC--;                                                     \
    adrmode(ticks);                                           \
    if (mpu->callbacks->call[ea])                             \
    {                                                         \
        word addr;                                            \
        externalise();                                        \
        if ((addr = mpu->callbacks->call[ea](mpu, ea, 0x20))) \
        {                                                     \
            internalise();                                    \
            PC = addr;                                        \
            fetch();                                          \
            next();                                           \
        }                                                     \
    }                                                         \
    PC = ea;                                                  \
    fetch();                                                  \
    next();

#define rts(ticks, adrmode) \
    tick(ticks);            \
    PC = pop();             \
    PC |= (pop() << 8);     \
    PC++;                   \
    fetch();                \
    next();

#define brk(ticks, adrmode)                                          \
    tick(ticks);                                                     \
    PC++;                                                            \
    push(PC >> 8);                                                   \
    push(PC & 0xff);                                                 \
    push(P | flagX | flagB);                                                 \
    /* http://www.6502.org/tutorials/65c02opcodes.html - unlike      \
     * the 6502, the 65C02 clears D on BRK.                          \
     */                                                              \
    P &= ~flagD;                                                     \
    P |= flagI;                                                      \
    {                                                                \
        word hdlr = getMemory(0xfffe) + (getMemory(0xffff) << 8);    \
        if (mpu->callbacks->call[hdlr])                              \
        {                                                            \
            word addr;                                               \
            externalise();                                           \
            if ((addr = mpu->callbacks->call[hdlr](mpu, PC - 2, 0))) \
            {                                                        \
                internalise();                                       \
                hdlr = addr;                                         \
            }                                                        \
        }                                                            \
        PC = hdlr;                                                   \
    }                                                                \
    fetch();                                                         \
    next();

#define rti(ticks, adrmode) \
    tick(ticks);            \
    P = pop();              \
    PC = pop();             \
    PC |= (pop() << 8);     \
    fetch();                \
    next();

#define nop(ticks, adrmode) \
    adrmode(ticks);         \
    fetch();                \
    tick(ticks);            \
    next();

/* determine addr and instruction before calling fetch(), otherwise the GNU C
 * version gets it wrong */
#define ill(ticks, adrmode)                                               \
    {                                                                     \
        word addr = PC - 1;                                               \
        byte instruction = memory[addr];                                  \
        tick(ticks);                                                      \
        if (mpu->callbacks->illegal_instruction[instruction])             \
        {                                                                 \
            adrmode(ticks);                                               \
            externalise();                                                \
            if (addr = (mpu->callbacks->illegal_instruction[instruction]( \
                    mpu, addr, instruction)))                             \
            {                                                             \
                mpu->registers->pc = addr;                                \
            }                                                             \
            internalise();                                                \
            fetch();                                                      \
            next();                                                       \
        }                                                                 \
        else                                                              \
        {                                                                 \
            adrmode(ticks);                                               \
            fetch();                                                      \
            next();                                                       \
        }                                                                 \
    };

#define phR(ticks, adrmode, R) \
    fetch();                   \
    tick(ticks);               \
    push(R);                   \
    next();

#define pha(ticks, adrmode) phR(ticks, adrmode, A)
#define phx(ticks, adrmode) phR(ticks, adrmode, X)
#define phy(ticks, adrmode) phR(ticks, adrmode, Y)
#define php(ticks, adrmode) phR(ticks, adrmode, P | flagX | flagB)

#define plR(ticks, adrmode, R) \
    fetch();                   \
    tick(ticks);               \
    R = pop();                 \
    setNZ(R & 0x80, !R);       \
    next();

#define pla(ticks, adrmode) plR(ticks, adrmode, A)
#define plx(ticks, adrmode) plR(ticks, adrmode, X)
#define ply(ticks, adrmode) plR(ticks, adrmode, Y)

#define plp(ticks, adrmode) \
    fetch();                \
    tick(ticks);            \
    P = pop();              \
    next();

#define clF(ticks, adrmode, F) \
    fetch();                   \
    tick(ticks);               \
    P &= ~F;                   \
    next();

#define clc(ticks, adrmode) clF(ticks, adrmode, flagC)
#define cld(ticks, adrmode) clF(ticks, adrmode, flagD)
#define cli(ticks, adrmode) clF(ticks, adrmode, flagI)
#define clv(ticks, adrmode) clF(ticks, adrmode, flagV)

#define seF(ticks, adrmode, F) \
    fetch();                   \
    tick(ticks);               \
    P |= F;                    \
    next();

#define sec(ticks, adrmode) seF(ticks, adrmode, flagC)
#define sed(ticks, adrmode) seF(ticks, adrmode, flagD)
#define sei(ticks, adrmode) seF(ticks, adrmode, flagI)

#include "6502data.h"

void M6502_irq(M6502* mpu)
{
    if (!(mpu->registers->p & flagI))
    {
        mpu->memory[0x0100 + mpu->registers->s--] =
            (byte)(mpu->registers->pc >> 8);
        mpu->memory[0x0100 + mpu->registers->s--] =
            (byte)(mpu->registers->pc & 0xff);
        mpu->memory[0x0100 + mpu->registers->s--] = (mpu->registers->p & ~flagB) | flagX;
        mpu->registers->p |= flagI;
        mpu->registers->p &= ~flagD;
        mpu->registers->pc = M6502_getVector(mpu, IRQ);
    }
}

void M6502_nmi(M6502* mpu)
{
    mpu->memory[0x0100 + mpu->registers->s--] = (byte)(mpu->registers->pc >> 8);
    mpu->memory[0x0100 + mpu->registers->s--] =
        (byte)(mpu->registers->pc & 0xff);
    mpu->memory[0x0100 + mpu->registers->s--] = (mpu->registers->p & ~flagB) | flagX;
    mpu->registers->p |= flagI;
    mpu->registers->p &= ~flagD;
    mpu->registers->pc = M6502_getVector(mpu, NMI);
}

void M6502_reset(M6502* mpu)
{
    mpu->registers->p &= ~flagD;
    mpu->registers->p |= flagI;
    mpu->registers->pc = M6502_getVector(mpu, RST);
}

/* the compiler should elminate all call to this function */

static void oops(void)
{
    fprintf(stderr, "\noops -- instruction dispatch missing\n");
}

void M6502_run(M6502* mpu)
{
#define fetch()
#define next() break

#define dispatch(num, name, mode, cycles) \
    case 0x##num:                         \
        name(cycles, mode);               \
        next();

#define end() }

    register byte* memory = mpu->memory;
    register word PC;
    word ea;
    byte A, X, Y, P, S;
    M6502_Callback* readCallback = mpu->callbacks->read;
    M6502_Callback* writeCallback = mpu->callbacks->write;

#define internalise()      \
    A = mpu->registers->a; \
    X = mpu->registers->x; \
    Y = mpu->registers->y; \
    P = mpu->registers->p; \
    S = mpu->registers->s; \
    PC = mpu->registers->pc

#define externalise()      \
    mpu->registers->a = A; \
    mpu->registers->x = X; \
    mpu->registers->y = Y; \
    mpu->registers->p = P; \
    mpu->registers->s = S; \
    mpu->registers->pc = PC

    internalise();

    switch (memory[PC++])
    {
        do_insns(dispatch);
    }

    externalise();
#undef internalise
#undef externalise
#undef fetch
#undef next
#undef dispatch
}

int M6502_disassemble(M6502* mpu, word ip, char buffer[64])
{
    char* s = buffer;
    byte* b = mpu->memory + ip;

    switch (b[0])
    {
#define _implied return 1;
#define _immediate             \
    sprintf(s, "#%02X", b[1]); \
    return 2;
#define _zp                   \
    sprintf(s, "%02X", b[1]); \
    return 2;
#define _zpx                    \
    sprintf(s, "%02X,X", b[1]); \
    return 2;
#define _zpy                    \
    sprintf(s, "%02X,Y", b[1]); \
    return 2;
#define _abs                            \
    sprintf(s, "%02X%02X", b[2], b[1]); \
    return 3;
#define _absx                             \
    sprintf(s, "%02X%02X,X", b[2], b[1]); \
    return 3;
#define _absy                             \
    sprintf(s, "%02X%02X,Y", b[2], b[1]); \
    return 3;
#define _relative                              \
    sprintf(s, "%04X", ip + 2 + (int8_t)b[1]); \
    return 2;
#define _zpr \
    sprintf(s, "%02X,%04X", b[1], ip + 2 + (int8_t)b[2]); \
    return 3;
#define _indirect                         \
    sprintf(s, "(%02X%02X)", b[2], b[1]); \
    return 3;
#define _indzp                  \
    sprintf(s, "(%02X)", b[1]); \
    return 2;
#define _indx                     \
    sprintf(s, "(%02X,X)", b[1]); \
    return 2;
#define _indy                     \
    sprintf(s, "(%02X),Y", b[1]); \
    return 2;
#define _indabsx                            \
    sprintf(s, "(%02X%02X,X)", b[2], b[1]); \
    return 3;

#define disassemble(num, name, mode, cycles) \
    case 0x##num:                            \
        s += sprintf(s, "%s ", #name);       \
        _##mode
        do_insns(disassemble);
#undef _do
    }

    return 0;
}

void M6502_dump(M6502* mpu, char buffer[64])
{
    M6502_Registers* r = mpu->registers;
    uint8_t p = r->p;
#define P(N, C) (p & (1 << (N)) ? (C) : '-')
    sprintf(buffer,
        "PC=%04X SP=%04X A=%02X X=%02X Y=%02X P=%02X %c%c%c%c%c%c%c%c",
        r->pc,
        0x0100 + r->s,
        r->a,
        r->x,
        r->y,
        r->p,
        P(7, 'N'),
        P(6, 'V'),
        P(5, '?'),
        P(4, 'B'),
        P(3, 'D'),
        P(2, 'I'),
        P(1, 'Z'),
        P(0, 'C'));
#undef P
}

static void outOfMemory(void)
{
    fflush(stdout);
    fprintf(stderr, "\nout of memory\n");
    abort();
}

M6502* M6502_new(
    M6502_Registers* registers, M6502_Memory memory, M6502_Callbacks* callbacks)
{
    M6502* mpu = calloc(1, sizeof(M6502));
    if (!mpu)
        outOfMemory();

    if (!registers)
    {
        registers = (M6502_Registers*)calloc(1, sizeof(M6502_Registers));
        mpu->flags |= M6502_RegistersAllocated;
    }
    if (!memory)
    {
        memory = (uint8_t*)calloc(1, sizeof(M6502_Memory));
        mpu->flags |= M6502_MemoryAllocated;
    }
    if (!callbacks)
    {
        callbacks = (M6502_Callbacks*)calloc(1, sizeof(M6502_Callbacks));
        mpu->flags |= M6502_CallbacksAllocated;
    }

    if (!registers || !memory || !callbacks)
        outOfMemory();

    mpu->registers = registers;
    mpu->memory = memory;
    mpu->callbacks = callbacks;

    return mpu;
}

void M6502_delete(M6502* mpu)
{
    if (mpu->flags & M6502_CallbacksAllocated)
        free(mpu->callbacks);
    if (mpu->flags & M6502_MemoryAllocated)
        free(mpu->memory);
    if (mpu->flags & M6502_RegistersAllocated)
        free(mpu->registers);

    free(mpu);
}
