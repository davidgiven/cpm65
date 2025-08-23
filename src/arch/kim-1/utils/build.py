from build.llvm import llvmprogram, llvmclibrary

llvmclibrary(
    name="imu-k1013",
    srcs=["./imu-k1013.S"],
    deps=["include"],
    hdrs={"k-1013.inc": "src/arch/kim-1/k-1013.inc"},
)

llvmclibrary(
    name="imu-sdshield",
    srcs=["./imu-sdshield.S"],
    deps=["include"],
    hdrs={
        "sdshield.inc": "src/arch/kim-1/sdshield.inc",
        "parproto.inc": "src/arch/kim-1/parproto.inc",
    },
)

llvmclibrary(
    name="sdshield",
    srcs=["./sdshield.S"],
    deps=["include"],
    hdrs={"parproto.inc": "src/arch/kim-1/parproto.inc"},
)

llvmprogram(
    name="format",
    srcs=["./format.S"],
    cflags=["-I src/arch/kim-1"],
    deps=[
        "include",
        "src/arch/kim-1/k-1013.inc",
    ],
)

llvmprogram(
    name="imu_k1013",
    srcs=["./imu.S"],
    cflags=["-I src/arch/kim-1"],
    deps=[
        "include",
        "src/arch/kim-1/k-1013.inc",
        ".+imu-k1013",
    ],
)

llvmprogram(
    name="imu_sdshield",
    srcs=["./imu.S"],
    cflags=["-I src/arch/kim-1"],
    deps=[
        "include",
        "src/arch/kim-1/parproto.inc",
        "src/arch/kim-1/sdshield.inc",
        ".+imu-sdshield",
        ".+sdshield",
        "src/arch/kim-1+pario",
    ],
)
