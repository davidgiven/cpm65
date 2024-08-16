# Working Development Tree For the Fuzix Compiler Kit

## Design

cc0 is a tool that tokenizes a C file and handles all the messy
number conversions and string quoting to produce a token stream for a
compiler proper to consume. It also extracts all the identifiers and numbers
them, before writing them out in a table.

cc1 takes the tokenized stream and generates an output stream that consists
of descriptors of program structure (function/do while/statement etc) with
expression trees embedded within.

cc2 will then turn this into code.

In theory it ought to also be possible to add a cc1b that further optimizes the
trees from cc1.

## Status

The compiler is currently used to build the Fuzix OS for 8080, 8085 and Z80
and can cross build itself to run natively on these systems. The core code
should be reasonably stable. There is a lot of performance work to do on
the compiler itself and there are still a couple of deviations from spec
that would be nice to fix. The backends for 8080/5/Z80 should be fairly
stable but are being used to experiment with improvements.

The other processor trees are very much a work in progress.

## Installation

As a cross compiler the front end expects it all to live in `/opt/fcc/`. The
tool chain provides the compiler front end and phases. For cpp for now it
uses the gcc preprocessor on Linux and DECUS cpp on Fuzix.

Either make the `/opt/fcc` directory and make it owned by your user or do
the install phase with appropriate privileges.

The assembler and loader tools required live in the
[Fuzix-Bintools repository](https://github.com/EtchedPixels/Fuzix-Bintools).
To build it all first clone the Fuzix-Bintools respository and `make install`.
Then make sure `/opt/fcc` is on your path.

Now clone this repository. In the Fuzix-Compiler-Kit directory do:

```
make bootstuff
make install
```

This will build a bootstrap then build the full tools and install them.
## Intended C Subset

The goal is to support the following

### Types

* char, short, int, long, signed and unsigned
* float, double
* struct, union
* enum
* typedef

Currently the compiler requires that the target types all fit into the host
unsigned long type.

Currently the compiler hardcodes assumptions that a char is 8bits, short
16bit and long 32bits (see tree.c:constify and helpers). This needs to be
addressed.

### Storage classes

auto, static, extern, typedef, register

register is dependent upon the backend.

### C Syntax

* standard keywords and flow control
* labels, and goto
* statements and expressions
* declarations
* ANSI C function declarations

### Intentionally Omitted

Things that add size and complexity or are just pointless.

* K&R function declarations
* Most C95 stuff - wide char, digraph etc
* Most C99 bloat by committee
* C11 bloat by committee
* struct/union passing, struct/union returns and other related badness
* bitfields
* const and volatile typing. To do these makes type handling really really tricky. They are accepted so that code with them can build and some magic tricks are done to get volatile right

###

Known incompatibilities (some to be fixed)

* The constant value -32768 does not always get typed correctly. The reason for this is a complicated story about how cc0/cc1 interact.
* Many C compilers permit (void) to 'cast' the result of a call away, we do not.
* Local variables have a single function wide scope not a block scope

## Backend Status

### 1802

An experimental bytecode engine for the 1802. The bytecode side of the
generation appears to be functional (except for floats) and the bytecode
simulation passes the basic tests. The next steps are a bytecode format
assembler for user bytecode pieces, and to start to build and debug the
actual 1802 interpreter. It should also be a good basis for any other
CPU needing this sort of treatment.

### 6303/6803/68HC11

This is an early sketch only based upon the CC6303 code generation and
support code.

### 6502

Early development code for a 6502/65C02 backend. Before this can be
effective there will need to be some work on rewriting subtrees to use byte
operations when possible.

### 65C816

An intial 65C816 native port that passes the test suite but probaly has some
bugs left to find. As this port is designed for Fuzix and run in any bank it
uses Y as the C stack pointer and uses the CPU stack for temporary values
during expression evaluation and the all actual call/return addresses. Split
code/data is supported but not multiple data or code banks in one application
(that is pointers are 16bit). Going beyond that gets very ugly very fast as on
8086.

### 8080/8085

The compiler generates reasonable 8080 code and knows how to use call stubs
for argument fetching/storing to get compact code at a performance cost if
requested. On the 8085 extensive use is made of LDSI, LHLX and SHLX to get
good compact code generation.

Long maths is quite slow but is not trivial to optimize, particularly on the
8080 processor. There is also no option to use RST calls for the most common
bits of code for compactness (quite possibly worth 1Kb or more for some
stuff). The code generator does not know the fancy tricks for turning
constant divides into shift/multiply sets.

The BC register is used as a register variable for either byte or word
constants, or a byte pointer. As there is no word sized load/store via BC or
easy way to do it the BC register pair is not used for other pointer sizes.

Signed comparison and sign extension are significantly slower than unsigned.
This is an instruction set limitation.

### Z8

This port now passes all of the self tests and the code coverage compile
tests. It has not yet been used except on test sets so probably contains
a few bugs. Split I/D is supported.

### Z80 / Z180

The Z80 code generator will generate reasonable Z80 code. The processor
itself is difficult to use for C as fetching objects from the stack is slow
as on the 8080. The compiler will use BC, IX and IY for register variables
and knows how to use offsets from IX or IY when working with structs.

If IX or IY are free they will be used as a frame pointer, if not the
compiler assumes the programmer knows what they are doing and will assign
them as register variables whilst using helpers for the locals.

The Z180 is not yet differentiated. This will only matter for the support
library code and maybe inlining a few specific multiplication cases.

### ThreadCode

An initial backend that turns the C input into a series of helper references
and data. This can easily be tweaked to make them calls, and peephole rules
used to clean up or re-arrange them a bit to suit any need or turn it into
byytecode etc.

### Default

This is a simple test backend the just turns the input into a lot of calls.
It is intended as a reference only although it may be useful for processors
that require a threadcode implementation or to build an interpreted backend.

## Internals

### cc0

Takes input from stdin and outputs tokens to stdout. The core of the logic
is pretty basic, the only oddity is using strchr() in a few places because
it's often hand optimized assembler. Tokens are 16bits. C has some specific
rules on tokenizing which make it simple at the cost of producing unexpected
results from stuff like x+++++y; (x++ ++ +y).

All names are translated into a 16bit token number. So for example every
occurence of "fred" might be 0x8004. The cc0 stage has no understanding of
C scoping so 0x8004 isn't tied to any kind of scope, merely a group of
letters.

After tokenizing it writes the symbol table out to disk as well. It turns
out that the compiler phase has no use at all for symbol names and they
take a lot of space to store and slow down comparisons.

### cc1

This is essentially a hand coded recursive descent parser. Higher level
constructs are described by headers and footers. Within these blocks the
compiler stores expression trees per statement. Trees do not span statements
nor does the compiler do anything at a higher level. There is enough
information to turn functions or even entire programs into a single tree if
the code generator or an optimizer pass wished.

The biggest challenge on a small machine is the memory management. To keep
things tight types are packed into 16bits. Where the type is complex it
contains an index to an object in the symbol table which describes the type
in question (and if the type is named also has the type naming attached).

Various per object fields are packed into runs of 16bit values, such as
struct field information and array sizes.

To maximise memory efficiency without losing the checking the compiler packs
all functions with the same signature into the same type. As most functions
actually have one of a very small number of prototypes this saves a lot of
room.

### cc2

For now just testing a very simple left hand walking code generator with
minimal awareness of consts and names that can be directly accessed. This
should suit simpler processors like the 6502, 680x, 8080, 8085 etc but isn't
a good model for register oriented ones.

On the other hand it's ludicrously easy to change it to produce fairly bad
code for any processor you want.

## Credits

The expression parser was created by turning the public domain SmallC 3.0 one
into a more traditional tree building recursive parser and testing it in
SmallC. The rest of the code is original although the design is influenced by
several small C subset compilers and also ANSI pcc.

## Licence

Compiler (not any runtime)	:	GPLv3

copt is from Z88DK. Z88DK is under the Clarified Artistic License
