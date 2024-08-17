tinycpp - a small, embeddable C-style preprocessor
==================================================

tinycpp was created with the intention of having a C-style preprocessor
for use in an assembler i'm working on.
the particular issue i faced with standard C preprocessors is that
multiline-macros are expanded into a single line. this basically
requires to add something like ';' to the assembler language, to support
several expressions in a single line.

one of the design goals from the start was to read the input token by
token, instead of slurping the entire file into memory.
this, unfortunately, required some trickery to get the right behaviour
in some cases, but should save a lot of memory on big files
(theoretically, it should be able to process gigabyte-big files, while
only consuming a few MBs ram (depending on the amount of macros that
need to be stored)).

apart from that, tinycpp pretty much behaves like your standard cpp.

it's self-hosting: it can preprocess its own source, and the result
compiles fine, so it's quite complete (tested with musl libc headers).

size
----
the 2 TUs used by the preprocessor library are less than 2 KLOC combined.
additionally about 500 LOC of list and hash header implementations from
libulz are used. this is still a lot less than ucpp's 8 KLOC-ish
implementation. not as tiny as i'd like, but a C preprocessor is a
surprisingly complex beast.

speed
-----
speed is slightly slower than GNU cpp, and slightly faster than mcpp on
a 12MB testfile which defines, undefs and uses thousands of macros.

differences to standard C preprocessors
---------------------------------------

- "if" evaluation treats all numeric literals as integers, even if they
  have L/U/LL/LLU suffixes. this is probably the biggest blocker from
  becoming a fully compliant C preprocessor.
  shouldn't be hard to support though.
- widechar literals in conditionals are treated as if they were a single
  non-wide character.
- multiline macros keep newline characters, which doesn't cause any
  issues, apart from making it harder to diff against other CPPs output.
  (`__LINE__` macro behaves as expected, though, in that it shows the same
  line number for all expanded lines).
- no predefined macros such as `__STDC__`. you can set them yourself, if
  you like.
- a few test cases of mcpp fail. these are cornercases that are usually
  not encountered in the wild.
  e.g. https://github.com/ned14/mcpp/blob/master/test-c/n_5.c
- lines starting w/ comments like `/**/` followed by preprocessor directives
  are currently not detected as such. this is because comments are removed
  on the fly, not in a previous pass. it shouldn't be very hard to support
  it, though.
- no digraphs and trigraphs supported.
- multiple sequential whitespace characters are preserved.
- max token length is 4095, though this can easily be changed.
  many CPPs happily process much longer tokens, even though the standard
  doesn't require it.
- some built-ins like `__TIME__` and `__DATE__` are missing, but you can
  define them yourself if needed. `__LINE__` and `__FILE_`_ were added,
  as they're used by musl's headers.
- the printed diagnostics are sometimes not very helpful.

anything else not mentioned here is supported (including varargs, pasting,
stringification, ...)

differences to other C preprocessor libraries
---------------------------------------------

the preprocessor interface takes a `FILE*` as input and one as output.
it doesn't try to provide a C token stream.
in order not to write to disk, you can use memory streams
(open_memstream() to create a writable stream, followed by fflush() to
make its contents available)

how to build
------------
clone the libulz library https://github.com/rofl0r/libulz, and point the
Makefile to the directory, or copy the 3 headers needed into the source
tree, then run `make`.

how to use
----------
look at `preproc.h` and `cppmain.c`, which implements the demo preprocessor
program.

acknowledgements
----------------
thanks go to mcpp's author, whose testsuite i extensively used.

