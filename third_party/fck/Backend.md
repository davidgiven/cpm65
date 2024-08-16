# The Compiler Backend

## Basics Of Operation

The front end of the compiler writes out a working file that consists of a
mix of expression trees, headers and footers. The latter carry information
that doesn't fit in the expression trees like the size of function
arguments, and whether it is void. They are also used for branching and
other block structure that could be in expression trees but would otherwise
require large function sized trees to be processed.

As there is not a lot of space on an 8bit micro the compiler mostly deals
with things at the statement level. Each tree fed to the backend is a C
statement along with some additional information to indicate whether the
result is needed, whether operations can be ignored and whether condition
codes or values are wanted

## Tree Structure

Each node in the expression tree is one of three types

### Terminal Node

This is a value or similar and has no children.

### Unary Node

This is used for unary expressions. It has only a right hand child which is
the expression the unary operator applies to. This is usually the one to the
right of it but it depends which way the operator binds.

### Binary Node

This is used for an expression with two values (addition for example). These
nodes have a left and right expression. Some apparently unary nodes are
turned into binary nodes because they have hidden properties. Things like
"++" are handled this way because the amount added depends upon the type of
the object pointed to.

## Tree Processing

### Rewriting

Once the expression tree is loaded each node is passed to gen_rewrite_node
working from the bottom left in the same order as code generation will then
follow. This allows the target to rewrite sections of the tree, or re-order
operations to suit. Once all the tree has been fed to gen_rewrite_node the
code generation begins.

### Code Generation

At its simplest the compiler recursively tries to evaluate the sub
expressions of each node and then the node itself. It starts with the left
hand side if present and then the right. If a left hand is evaluated then it
is evaluated into the working register (the running result) and this is then
stacked. The right hand side is then evaluated if present then gen_node()
generates the operator. Operators act on the working register and if binary on
the top of the stack - which is removed.

If you are familiar with forth then the output of the front end expression
trees when walked this way look much the same. For example "2 + 5" becomes
"2 5 + ".

This is an easy way to generate correct but awful code. Most of the backends
thus have the concept of an "easy" expression. To begin they rewrite local, 
argument and global/static accesses into a single node and try to re-order
bits of the expression they can so the simplest parts are on the right.

#### The gen_direct function

During tree processing gen_direct is called for each node that has a left
hand side before the value is pushed. An easy expression is one where the
operator and the right hand subtree can be computed without trashing the
working register. This varies by processor. The 8080 for example is capable
of directly loading constants and globals but not local variables without
disturbing the working value in HL.

This takes the code from 

````
	lhld,_arg1
	push h
	lhld _arg2
	pop d
	dad d
````

to the rather better

````
	lhld _arg1
	xchg
	lhld _arg2
	xchg
	dad d
````

or after the peephole optimizer

````
	lhld _arg1
	xchg
	lhld _arg2
	dad d
````

Other processors can also dereference local variables this way, and many
have register/memory operators so they can act directly on the tree. The
65C816 has the data stack in Y (arguments and locals) and can generate

````
	lda _arg1
	clc
	adc _arg2
````

Or with local references

````
	lda arg1,y
	clc
	adc arg2,y
````

For most cases that backend can also handle dereferences to any "easy"
expression so that stuff like local struct pointer dereferences can be kept
"easy". For example

````
	unsigned foo(struct x *a, struct x *b) {
		return a->val + b->val;
	}
````

can be turned into

````
	ldx arg1,y
	lda 2,x
	ldx arg2,y
	clc
	adc 2,x
````

#### The gen_shortcut function

This is called as the tree walk descends and if it returns one the entire
subtree below it is assumed to have been processed by the routine. It allows
the easy removal of unreachable code, and also can be used to do things
like evaluate an expression in a different order. For example some backends
use this to evalute either the left or right hand side of an assignment
first according to which side is "easy" (if any) in order to generate better
assignment code according to the structure of the assignment.

#### The gen_uni_direct function

This works similarly to the above two for unary nodes. If it returns one the
entire subtree is assumed generated.

#### Default handler

Any node that is not handled by the methods and finally gen_node is turned
into a subroutine call. Thus the default output when you start with a blank
backend is basically threaded subroutine calls. Because long types are
difficult to handle well on many platforms with few registers a lot of
targets make heavy use of helpers for these.
 