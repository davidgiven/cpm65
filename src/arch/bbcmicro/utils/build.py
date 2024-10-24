from build.llvm import llvmprogram

llvmprogram(
    name="8080_ovl_loader",
    srcs=["./8080_ovl_loader.S"],
    deps=[
        "include",
    ],
    cflags=["-DMASTER128"],
)
