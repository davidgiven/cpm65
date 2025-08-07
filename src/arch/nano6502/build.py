from build.ab import simplerule
from tools.build import mkcpmfs
from build.llvm import llvmrawprogram
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    BIG_SCREEN_APPS,
    PASCAL_APPS,
    SERIAL_APPS,
    SERIAL_SCREEN_APPS,
    FORTH_APPS,
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
    items={
        "0:ccp.sys@sr": "src+ccp",
        "1:colorfg.com": "src/arch/nano6502/utils+colorfg",
        "1:colorbg.com": "src/arch/nano6502/utils+colorbg",
        "1:ledtest.com": "src/arch/nano6502/utils+ledtest",
        "1:baudrate.com": "src/arch/nano6502/utils+baudrate",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | BIG_SCREEN_APPS
    | PASCAL_APPS
    | SERIAL_APPS
    | SERIAL_SCREEN_APPS
    | FORTH_APPS,
)

mkcpmfs(
    name="emptycpmfs",
    format="generic-1m",
    items="",
)

simplerule(
    name="diskimage",
    ins=[
        ".+cpmfs",
        ".+emptycpmfs",
        ".+nano6502",
        "src/bdos",
        "./buildimage.py",
    ],
    outs=["=nano6502.img"],
    commands=[
        "rm -f $[outs[0]]",
        "$[ins[4]] $[ins[2]] $[ins[3]] $[ins[0]] $[ins[1]] $[outs[0]]",
    ],
    label="IMG",
)

simplerule(
    name="sysimage",
    ins=[
        ".+cpmfs",
        ".+emptycpmfs",
        ".+nano6502",
        "src/bdos",
        "./buildsysimage.py",
    ],
    outs=["=nano6502_sysonly.img"],
    commands=[
        "rm -f $[outs[0]]",
        "$[ins[4]] $[ins[2]] $[ins[3]] $[ins[0]] $[ins[1]] $[outs[0]]",
    ],
    label="IMG",
)
