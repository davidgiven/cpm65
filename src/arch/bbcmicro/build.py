from build.ab import normalrule
from tools.build import mkdfs, mkcpmfs, mametest
from build.llvm import llvmrawprogram
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
    PASCAL_APPS,
)

llvmrawprogram(
    name="bios",
    srcs=["./bbcmicro.S", "./mos.inc"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./bbcmicro.ld",
)

mkcpmfs(
    name="cpmfs",
    format="bbc192",
    items={"0:ccp.sys@sr": "src+ccp"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | SCREEN_APPS_SRCS
    | PASCAL_APPS,
)

mkcpmfs(
    name="cpmfs2",
    format="bbc192",
    items={
        "0:ccp.sys@sr": "src+ccp",
        "2:8080.com": "src/arch/bbcmicro/utils+8080_ovl_loader",
        "2:8080.ovl": "third_party/atari8080/8080-bbc.ovl",
        "2:halt.com": "third_party/atari8080/HALT.COM",
        "2:stat.com": "third_party/atari8080/STAT.COM",
        "2:dump.com": "third_party/atari8080/DUMP.COM",
        "2:pip.com": "third_party/atari8080/PIP.COM",
        "2:zork1.com": "third_party/atari8080/ZORK1.COM",
        "2:zork1.dat": "third_party/atari8080/ZORK1.DAT",
        "2:tst8080.com": "third_party/atari8080/TST8080.COM",
        "2:8080pre.com": "third_party/atari8080/8080PRE.COM",
        "2:8080exm.com": "third_party/atari8080/8080EXM.COM",
        "2:cputest.com": "third_party/atari8080/CPUTEST.COM",

    }
    | SCREEN_APPS
)

mkdfs(
    name="diskimage",
    out="bbcmicro.ssd",
    title="CP/M-65",
    opt=2,
    items={
        "!boot@0x0400": ".+bios",
        "bdos": "src/bdos",
        "cpmfs": ".+cpmfs",
    },
)

mkdfs(
    name="diskimage2",
    out="bbcmicro2.ssd",
    title="CP/M-65",
    opt=2,
    items={
        "!boot@0x0400": ".+bios",
        "bdos": "src/bdos",
        "cpmfs": ".+cpmfs2",
    },
)

mametest(
    name="mametest",
    target="bbcm",
    diskimage=".+diskimage",
    imagetype=".img",
    script="./mame-test.lua",
)
