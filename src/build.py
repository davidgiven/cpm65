from build.llvm import llvmprogram

llvmprogram(name="bdos", srcs=["./bdos.S"], deps=["include"])

llvmprogram(
    name="ccp", srcs=["./ccp.S"], deps=["include", "lib+bdos", "lib+xfcb"]
)
