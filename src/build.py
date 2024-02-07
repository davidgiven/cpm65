from build.llvm import llvmprogram

llvmprogram(
    name="ccp", srcs=["./ccp.S"], deps=["include", "lib+bdos", "lib+xfcb"]
)
