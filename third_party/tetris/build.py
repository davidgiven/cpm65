from build.ab import Rule, Target, Targets, simplerule
from build.llvm import llvmprogram
from tools.build import unixtocpm

llvmprogram(
    name="tetris",
    srcs=["./tetris.c"],
    deps=["lib+cpm65"]
)
