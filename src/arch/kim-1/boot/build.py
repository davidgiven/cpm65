from build.llvm import llvmrawprogram

llvmrawprogram (
    name="boot.bin",
    srcs=["./boot.S"],
    linkscript="./boot.ld",
)

llvmrawprogram (
    name="bootsd.bin",
    srcs=["./bootsd.S"],
    linkscript="./boot.ld",
)