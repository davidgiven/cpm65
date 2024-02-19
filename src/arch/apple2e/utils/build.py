from build.llvm import llvmprogram

llvmprogram(
    name="scrndrv",
    srcs=["./scrndrv.S"],
#    cflags=["-DAPPLE2E"],
    cflags=["-DAPPLE2PLUS"],
    deps=[
        "include",
        "src/arch/apple2e+common",
    ],
)
