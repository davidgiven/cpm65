from build.llvm import llvmprogram

llvmprogram( name="tty540b", srcs=["./tty540b.S"], deps=[ "include", ],)
llvmprogram( name="scrvt100", srcs=["./scrvt100.S"], deps=[ "include", ],)
