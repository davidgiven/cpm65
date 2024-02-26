from build.llvm import llvmprogram

llvmprogram(
    name="ncopy",
    srcs=["./ncopy.c", "./neo6502.h"],
    deps=[
        "include",
    ],
)
