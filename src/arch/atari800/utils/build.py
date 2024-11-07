from build.llvm import llvmprogram

llvmprogram(name="setfnt", srcs=["./setfnt.c"], deps=["lib+cpm65"])

llvmprogram(
    name="tty80drv",
    srcs=["./tty80drv.S"],
    deps=[
        "include",
        "src/arch/atari800+headers",
        "third_party/fonts/atari+ivo3x6",
    ],
)

llvmprogram(
    name="8080_ovl_loader",
    srcs=["./8080_ovl_loader.S"],
    deps=[
        "include",
        "src/arch/atari800+headers",
    ],
)
