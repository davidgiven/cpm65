from build.ab import Rule, Target, Targets, simplerule
from build.llvm import llvmprogram

llvmprogram(
    name="tetris2",
    srcs=["./tetris2.c"],
    deps=["lib+cpm65"]
)
