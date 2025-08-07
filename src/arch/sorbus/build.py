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
    SERIAL_APPS,
    FORTH_APPS,
)

llvmrawprogram(
    name="sorbus",
    srcs=["./sorbus.S"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./sorbus.ld",
)

mkcpmfs(
    name="cpmfs",
    format="sorbus",
    items={"0:ccp.sys@sr": "src+ccp"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS
    | SERIAL_APPS
    | FORTH_APPS,
)

zip(
    name="diskimage",
    items={
        "BDOS": "src/bdos",
        "CPM": ".+sorbus",
        "CPMFS": ".+cpmfs",
    },
)
