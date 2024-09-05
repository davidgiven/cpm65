from build.ab import simplerule
from tools.build import mkcpmfs
from build.llvm import llvmrawprogram
from build.zip import zip
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    PASCAL_APPS,
)

llvmrawprogram(
    name="x16",
    srcs=["./x16.S"],
    deps=["include", "src/lib+bioslib", "src/arch/commodore+commodore_lib"],
    linkscript="./x16.ld",
)

mkcpmfs(
    name="cpmfs",
    format="generic-1m",
    items={"0:ccp.sys@sr": "src+ccp"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

zip(
    name="diskimage",
    items={
        "CPMFS": ".+cpmfs",
        "CPM": ".+x16",
        "BDOS": "src/bdos",
    },
)
