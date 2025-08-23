from build.ab import Rule, Target, Targets, simplerule
from build.llvm import llvmprogram
from tools.build import unixtocpm

llvmprogram(
    name="lbforth",
    srcs=["./lbforth.c"],
    deps=["lib+cpm65"],
)
