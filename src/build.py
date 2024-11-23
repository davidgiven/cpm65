from build.llvm import llvmprogram

llvmprogram(
    name="ccp", srcs=["./ccp.S"], deps=["include", "lib+bdos", "lib+xfcb"]
)

llvmprogram(
    name="ccp-tiny",
    srcs=["./ccp.S"],
    deps=["include", "lib+bdos", "lib+xfcb"],
    cflags=["-DTINY"],
)
