from build.ab import Rule, Target, Targets, simplerule
from build.llvm import llvmprogram

llvmprogram(
    name="tetris",
    srcs=["./tetris.c"],
    deps=["lib+cpm65"]
)
