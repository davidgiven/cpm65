from build.llvm import llvmclibrary

llvmclibrary(
    name="zmalloc",
    cflags=["-std=c23"],
    srcs=["./zmalloc.c"],
    hdrs={"third_party/zmalloc/zmalloc.h": "./zmalloc.h"},
    deps=["third_party/zmalloc/zmalloc.h"],
)
