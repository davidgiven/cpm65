from build.ab import simplerule
from tools.build import mkcpmfs
from build.llvm import llvmrawprogram
from third_party.projectl.build import l_as65c
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
)

l_as65c(
    name="main",
    srcs=["./main.asm"],
)

llvmrawprogram(
    name="bios",
    srcs=["./bios.S"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./bios.ld",
)

mkcpmfs(
    name="diskimage",
    format="generic-1440k",
    size=1440*1024,
    items={
        "0:ccp.sys@sr": "src+ccp",
        "0:bdos.sys@sr": "src/bdos",
        "0:cls.com": "apps+cls",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS,
)

simplerule(
    name="snes_cartridge",
    ins=[".+bios", ".+diskimage"],
    outs=["=cartridge.smc"],
    commands=[
        "cat {ins} > {outs[0]}"
    ],
    label="MKCARTRIDGE",)