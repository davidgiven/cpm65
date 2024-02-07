from build.ab import normalrule
from tools.build import mkdfs, mkcpmfs
from build.llvm import llvmrawprogram
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
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
    | BIG_APPS_SRCS,
)

normalrule(
    name="diskimage",
    ins=[
        ".+cpmfs",
        ".+x16",
        "src/bdos",
    ],
    outs=["x16.zip"],
    commands=[
        "zip -9qj {outs[0]} {ins}",
        r'printf "@ bdos+bdos\n@=BDOS\n" | zipnote -w {outs[0]}',
        r'printf "@ x16+x16\n@=CPM\n" | zipnote -w {outs[0]}',
        r'printf "@ x16+cpmfs.img\n@=CPMFS\n" | zipnote -w {outs[0]}',
    ],
    label="ZIP",
)
