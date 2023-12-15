from build.llvm import llvmclibrary

llvmclibrary(name="bdos", srcs=["./bdos.S"], deps=["include"])

llvmclibrary(name="xfcb", srcs=["./xfcb.S"], deps=["include"])
