#ifndef __m6502_h
#define __m6502_h


#include <stdio.h>
#include <stdint.h>

typedef struct _M6502		M6502;
typedef struct _M6502_Registers	M6502_Registers;
typedef struct _M6502_Callbacks	M6502_Callbacks;

typedef int   (*M6502_Callback)(M6502 *mpu, uint16_t address, uint8_t data);

typedef M6502_Callback	M6502_CallbackTable[0x10000];
typedef M6502_Callback	M6502_IllegalInstructionCallbackTable[0x100];
typedef uint8_t		M6502_Memory[0x10000];

enum {
  M6502_NMIVector= 0xfffa,  M6502_NMIVectorLSB= 0xfffa,  M6502_NMIVectorMSB= 0xfffb,
  M6502_RSTVector= 0xfffc,  M6502_RSTVectorLSB= 0xfffc,  M6502_RSTVectorMSB= 0xfffd,
  M6502_IRQVector= 0xfffe,  M6502_IRQVectorLSB= 0xfffe,  M6502_IRQVectorMSB= 0xffff
};

struct _M6502_Registers
{
  uint8_t   a;	/* accumulator */
  uint8_t   x;	/* X index register */
  uint8_t   y;	/* Y index register */
  uint8_t   p;	/* processor status register */
  uint8_t   s;	/* stack pointer */
  uint16_t pc;	/* program counter */
};

struct _M6502_Callbacks
{
  M6502_CallbackTable read;
  M6502_CallbackTable write;
  M6502_CallbackTable call;
  M6502_IllegalInstructionCallbackTable illegal_instruction;
};

struct _M6502
{
  M6502_Registers *registers;
  uint8_t	  *memory;
  M6502_Callbacks *callbacks;
  unsigned int	   flags;
};

enum {
  M6502_RegistersAllocated = 1 << 0,
  M6502_MemoryAllocated    = 1 << 1,
  M6502_CallbacksAllocated = 1 << 2
};

extern M6502 *M6502_new(M6502_Registers *registers, M6502_Memory memory, M6502_Callbacks *callbacks);
extern void   M6502_reset(M6502 *mpu);
extern void   M6502_nmi(M6502 *mpu);
extern void   M6502_irq(M6502 *mpu);
extern void   M6502_run(M6502 *mpu);
extern int    M6502_disassemble(M6502 *mpu, uint16_t addr, char buffer[64]);
extern void   M6502_dump(M6502 *mpu, char buffer[64]);
extern void   M6502_delete(M6502 *mpu);

#define M6502_getVector(MPU, VEC)			\
  ( ( ((MPU)->memory[M6502_##VEC##VectorLSB]) )		\
    | ((MPU)->memory[M6502_##VEC##VectorMSB] << 8) )

#define M6502_setVector(MPU, VEC, ADDR)						\
  ( ( ((MPU)->memory[M6502_##VEC##VectorLSB]= ((uint8_t)(ADDR)) & 0xff) )	\
    , ((MPU)->memory[M6502_##VEC##VectorMSB]= (uint8_t)((ADDR) >> 8)) )

#define M6502_getCallback(MPU, TYPE, ADDR)	((MPU)->callbacks->TYPE[ADDR])
#define M6502_setCallback(MPU, TYPE, ADDR, FN)	((MPU)->callbacks->TYPE[ADDR]= (FN))


#endif /*__m6502_h */
