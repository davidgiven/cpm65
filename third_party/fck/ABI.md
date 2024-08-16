# The current ABI for the finished backends

## 8080

- char is 8bit and defaults unsigned
- int/unsigned are 16bit
- long/unsigned long/float are 32bit
- upper 16bits of 32bit maths is accumulated in a memory location (hireg)
- BC is a register variable (integer or byte pointers only) and callee saved

Function arguments are passed on the stack and byte size arguments are
passed as words (upper byte undefined), to suit the 8080 push/pop
instructions. Function return is in HL. Function argument clean up is done
by the caller.

## 8085

- char is 8bit and defaults unsigned
- int/unsigned are 16bit
- long/unsigned long/float are 32bit
- upper 16bits of 32bit maths is accumulated in a memory location (hireg)
- BC is a register variable (integer or byte pointers only) and callee saved

Function arguments are passed on the stack and byte size arguments are
passed as words (upper byte undefined), to suit the 8080 push/pop
instructions. Function return is in HL. Function argument clean up is done
by the caller.

## Z80

- char is 8bit and defaults unsigned
- int/unsigned are 16bit
- long/unsigned long/float are 32bit
- upper 16bits of 32bit maths is accumulated in a memory location (hireg)
- BC is a register variable (integer or byte pointers only) and callee saved
- IX and IY are register variables (pointer only) and callee saved
- Alt registers are not used

Function arguments are passed on the stack and byte size arguments are
passed as words (upper byte undefined), to suit the 8080 push/pop
instructions. Function return is in HL. Function argument clean up is done
by the caller.

