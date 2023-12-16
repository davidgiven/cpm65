from build.ab import normalrule
from tools.build import mkcpmfs
from build.llvm import llvmrawprogram, llvmclibrary
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
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
    items={
        "0:ccp.sys": "src+ccp",
        "0:bdos.sys": "src+bdos",
        "0:setfnt.com": "src/arch/atari800/utils+setfnt",
        "0:tty80drv.com": "src/arch/atari800/utils+tty80drv",
        "0:olivetti.fnt": "third_party/fonts/atari/olivetti.fnt",
    }
    | MINIMAL_APPS
    | BIG_APPS,
)

normalrule(
    name="atari800_diskimage",
    ins=[".+atari800_rawdiskimage"],
    outs=["atari80.atr"],
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
    items={
        "0:ccp.sys": "src+ccp",
        "0:bdos.sys": "src+bdos",
        "0:setfnt.com": "src/arch/atari800/utils+setfnt",
        "0:tty80drv.com": "src/arch/atari800/utils+tty80drv",
        "1:olivetti.fnt": "third_party/fonts/atari/olivetti.fnt",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | SCREEN_APPS_SRCS,
)

normalrule(
    name="atari800hd_diskimage",
    ins=[".+atari800hd_rawdiskimage"],
    outs=["atari80hd.atr"],
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
    items={
        "0:ccp.sys": "src+ccp",
        "0:bdos.sys": "src+bdos",
        "0:setfnt.com": "src/arch/atari800/utils+setfnt",
        "0:tty80drv.com": "src/arch/atari800/utils+tty80drv",
        "1:olivetti.fnt": "third_party/fonts/atari/olivetti.fnt",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | SCREEN_APPS_SRCS,
)

normalrule(
    name="atari800xlhd_diskimage",
    ins=[".+atari800xlhd_rawdiskimage"],
    outs=["atari80xlhd.atr"],
    commands=[
        r"/usr/bin/printf '\x96\x02\xf0\xff\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > {outs[0]}",
        "cat {ins[0]} >> {outs[0]}",
    ],
    label="MAKEATR",
)
