from build.ab import normalrule
from tools.build import mkdfs, mkcpmfs
from build.llvm import llvmrawprogram
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    PASCAL_APPS,
)

llvmrawprogram(
    name="nano6502",
    srcs=["./nano6502.S"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./nano6502.ld",
)

mkcpmfs(
    name="cpmfs",
    format="generic-1m",
    items={"0:ccp.sys@sr": "src+ccp"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | PASCAL_APPS,
)

mkcpmfs(
    name="emptycpmfs",
    format="generic-1m",
    items="",
)

normalrule(
    name="diskimage",
    ins=[
        ".+cpmfs",
        ".+emptycpmfs",
        ".+nano6502",
        "src/bdos",
    ],
    outs=["nano6502.img"],
    commands=["rm -f {outs[0]}","./src/arch/nano6502/buildimage.py"],
    label="IMG",
)

normalrule(
    name="sysimage",
    ins=[
        ".+cpmfs",
        ".+nano6502",
        "src/bdos",
    ],
    outs=["nano6502_sysonly.img"],
    commands=["rm -f {outs[0]}","./src/arch/nano6502/buildsysimage.py"],
    label="IMG",
)

