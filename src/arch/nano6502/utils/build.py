from build.llvm import llvmprogram

llvmprogram(
    name="colorfg",
    srcs=["./colorfg.S"],
    deps=[
        "include",
    ],
)

llvmprogram(
    name="colorbg",
    srcs=["./colorbg.S"],
    deps=[
        "include",
    ],
)

llvmprogram(
    name="ledtest",
    srcs=["./ledtest.S"],
    deps=[
        "include",
    ],
)

llvmprogram(
    name="baudrate",
    srcs=["./baudrate.S"],
    deps=[
        "include",
    ],
)
