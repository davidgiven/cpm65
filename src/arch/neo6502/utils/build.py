from build.llvm import llvmprogram

llvmprogram(
    name="ncopy",
    srcs=["./ncopy.c", "./neo6502.h"],
    deps=[
        "include",
    ],
)

llvmprogram(
    name="nattr",
    srcs=["./nattr.c", "./neo6502.h"],
    deps=[
        "include",
    ],
)
