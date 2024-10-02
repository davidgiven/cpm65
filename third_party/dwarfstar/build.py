from build.ab import Rule, Target, Targets, simplerule
from build.llvm import llvmprogram
from tools.build import unixtocpm

llvmprogram(
    name="dwarfstar",
    cflags=["-Ithird_party/zmalloc"],
    srcs=["./dwarfstar.c"],
    deps=["lib+cpm65", "third_party/zmalloc+zmalloc"]
)
unixtocpm(name="ds_txt_cpm", src="./ds.txt")
