from build.ab import normalrule
from tools.build import mkcpmfs, mametest
from build.llvm import llvmrawprogram, llvmclibrary
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
    PASCAL_APPS,
)

llvmclibrary(name="headers", hdrs={"atari800.inc": "./atari800.inc"})

llvmrawprogram(
    name="atari800_bios",
    srcs=["./atari800.S"],
    deps=["include", "src/lib+bioslib", ".+headers"],
    linkscript="./atari800.ld",
)

mkcpmfs(
    name="atari800_rawdiskimage",
    format="atari90",
    bootimage=".+atari800_bios",
    size=128 * 720,
    items={
        "0:ccp.sys@sr": "src+ccp",
        "0:bdos.sys@sr": "src/bdos",
        "1:setfnt.com": "src/arch/atari800/utils+setfnt",
        "1:tty80drv.com": "src/arch/atari800/utils+tty80drv",
        "1:olivetti.fnt": "third_party/fonts/atari/olivetti.fnt",
    }
    | MINIMAL_APPS
    | BIG_APPS,
)

normalrule(
    name="atari800_diskimage",
    ins=[".+atari800_rawdiskimage"],
    outs=["atari800.atr"],
    commands=[
        r"/usr/bin/printf '\x96\x02\x80\x16\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > {outs[0]}",
        "cat {ins[0]} >> {outs[0]}",
    ],
    label="MAKEATR",
)

llvmrawprogram(
    name="atari800hd_bios",
    srcs=["./atari800.S"],
    deps=["include", "src/lib+bioslib", ".+headers"],
    cflags=["-DATARI_HD"],
    linkscript="./atari800hd.ld",
)

mkcpmfs(
    name="atari800hd_rawdiskimage",
    format="atarihd",
    bootimage=".+atari800hd_bios",
    size=128 * 8190,
    items={
        "0:ccp.sys@sr": "src+ccp",
        "0:bdos.sys@sr": "src/bdos",
        "1:setfnt.com": "src/arch/atari800/utils+setfnt",
        "1:tty80drv.com": "src/arch/atari800/utils+tty80drv",
        "1:amstrad.fnt": "third_party/fonts/atari/amstrad.fnt",
        "1:apricot.fnt": "third_party/fonts/atari/apricot.fnt",
        "1:eagle.fnt": "third_party/fonts/atari/eagle.fnt",
        "1:ibmega.fnt": "third_party/fonts/atari/ibmega.fnt",
        "1:mbytepc.fnt": "third_party/fonts/atari/mbytepc.fnt",
        "1:olivetti.fnt": "third_party/fonts/atari/olivetti.fnt",
        "1:phoenix.fnt": "third_party/fonts/atari/phoenix.fnt",
        "1:toshiba.fnt": "third_party/fonts/atari/toshiba.fnt",
        "1:verite.fnt": "third_party/fonts/atari/verite.fnt",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | SCREEN_APPS_SRCS
    | PASCAL_APPS,
)

normalrule(
    name="atari800hd_diskimage",
    ins=[".+atari800hd_rawdiskimage"],
    outs=["atari800hd.atr"],
    commands=[
        r"/usr/bin/printf '\x96\x02\xf0\xff\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > {outs[0]}",
        "cat {ins[0]} >> {outs[0]}",
    ],
    label="MAKEATR",
)

llvmrawprogram(
    name="atari800xlhd_bios",
    srcs=["./atari800.S"],
    deps=["include", "src/lib+bioslib", ".+headers"],
    cflags=["-DATARI_HD", "-DATARI_XL"],
    linkscript="./atari800xlhd.ld",
)

mkcpmfs(
    name="atari800xlhd_rawdiskimage",
    format="atarihd",
    bootimage=".+atari800xlhd_bios",
    size=128 * 8190,
    items={
        "0:ccp.sys@sr": "src+ccp",
        "0:bdos.sys@sr": "src/bdos",
        "1:setfnt.com": "src/arch/atari800/utils+setfnt",
        "1:tty80drv.com": "src/arch/atari800/utils+tty80drv",
        "1:setfnt.com": "src/arch/atari800/utils+setfnt",
        "1:amstrad.fnt": "third_party/fonts/atari/amstrad.fnt",
        "1:apricot.fnt": "third_party/fonts/atari/apricot.fnt",
        "1:eagle.fnt": "third_party/fonts/atari/eagle.fnt",
        "1:ibmega.fnt": "third_party/fonts/atari/ibmega.fnt",
        "1:mbytepc.fnt": "third_party/fonts/atari/mbytepc.fnt",
        "1:olivetti.fnt": "third_party/fonts/atari/olivetti.fnt",
        "1:phoenix.fnt": "third_party/fonts/atari/phoenix.fnt",
        "1:toshiba.fnt": "third_party/fonts/atari/toshiba.fnt",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | SCREEN_APPS_SRCS
    | PASCAL_APPS,
)

normalrule(
    name="atari800xlhd_diskimage",
    ins=[".+atari800xlhd_rawdiskimage"],
    outs=["atari800xlhd.atr"],
    commands=[
        r"/usr/bin/printf '\x96\x02\xf0\xff\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > {outs[0]}",
        "cat {ins[0]} >> {outs[0]}",
    ],
    label="MAKEATR",
)

mametest(
    name="mametest",
    target="a800xlp",
    diskimage=".+atari800_diskimage",
    imagetype=".atr",
    script="./mame-test.lua",
)
