from build.llvm import llvmrawprogram

llvmrawprogram (
    name="cpm65.bin",
    srcs=["./boot.S"],
    linkscript="./boot.ld",
)