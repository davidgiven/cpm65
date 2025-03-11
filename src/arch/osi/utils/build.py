from build.llvm import llvmprogram

llvmprogram( name="tty540b", srcs=["./tty540b.S"], deps=[ "include", ],)
llvmprogram( name="tty630", srcs=["./tty540b.S"], deps=[ "include", ], cflags=["-DOSI630"],)
