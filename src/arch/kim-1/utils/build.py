from build.llvm import llvmprogram,llvmclibrary

llvmclibrary(
    name="k-1013", srcs=["./k-1013.S"], cflags=["-I src/arch/kim-1"], deps=["include", "src/arch/kim-1/kim-1.inc", "src/arch/kim-1/k-1013.inc"]
)

llvmprogram(
    name="format",
    srcs=["./format.S"],
    cflags=["-I src/arch/kim-1"],
    deps=[
        "include",
        ".+k-1013",
        "src/arch/kim-1/k-1013.inc",
    ],
)

llvmprogram(
    name="imu",
    srcs=["./imu.S"],
    cflags=["-I src/arch/kim-1"],
    deps=[
        "include",
        "src/arch/kim-1/k-1013.inc",
    ],
)
