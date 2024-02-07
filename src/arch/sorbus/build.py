from build.ab import normalrule
from tools.build import mkdfs, mkcpmfs
from build.llvm import llvmrawprogram
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
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
    | BIG_APPS_SRCS,
)

normalrule(
    name="diskimage",
    ins=[
        ".+cpmfs",
        ".+sorbus",
        "src/bdos",
    ],
    outs=["sorbus.zip"],
    commands=[
        "zip -9qj {outs[0]} {ins}",
        r'printf "@ bdos+bdos\n@=BDOS\n" | zipnote -w {outs[0]}',
        r'printf "@ sorbus+sorbus\n@=CPM\n" | zipnote -w {outs[0]}',
        r'printf "@ sorbus+cpmfs.img\n@=CPMFS\n" | zipnote -w {outs[0]}',
    ],
    label="ZIP",
)
