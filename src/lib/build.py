from build.llvm import llvmclibrary

llvmclibrary(
    name="bioslib",
    srcs=["./biosentry.S", "./relocate.S", "./loader.S"],
    deps=["include"],
)
