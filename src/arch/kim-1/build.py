from build.ab import normalrule
from tools.build import mkimd, mkcpmfs
from build.llvm import llvmrawprogram
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    PASCAL_APPS,
)

llvmrawprogram(
    name="bios",
    srcs=["./kim-1.S"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./kim-1.ld",
)

mkcpmfs(
    name="cpmfs",
    format="k-1013",
    bootimage=".+bios",
    items={"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

mkimd(name="diskimage", src=".+cpmfs")