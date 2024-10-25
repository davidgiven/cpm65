from build.ab import simplerule
from build.tass64 import tass64
from tools.build import mkcpmfs
from build.llvm import llvmrawprogram, llvmcfile
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
)

llvmrawprogram(
    name="bios",
    srcs=["./loader.S", "./bios.S"],
    deps=["include", "src/lib+bioslib", "src/bdos+bdoslib"],
    cflags=[
        "-mcpu=mosw65c02",
    ],
    linkscript="./snes.ld",
)

mkcpmfs(
    name="diskimage",
    format="generic-1440k",
    size=1440 * 1024,
    items={
        "0:ccp.sys@sr": "src+ccp",
        "0:bdos.sys@sr": "src/bdos",
        "0:cls.com": "apps+cls",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS,
)

simplerule(
    name="font",
    ins=["src/arch/snes/tools+mkfont"],
    outs=["=4bpp.bin", "=2bpp.bin"],
    commands=["{ins[0]} {outs}"],
    label="MKFONT",
)

tass64(
    name="snes_cartridge_bin",
    srcs=[
        "./main.asm",
        "./snes.inc",
        ".+diskimage",
        ".+font",
        ".+bios",
    ],
    deps=[".+diskimage"],
    flags=[
        "--flat",
        "--ascii",
        #        "--case-sensitive",
        "-Wno-wrap-pc",
    ],
)

simplerule(
    name="snes_cartridge",
    ins=[".+snes_cartridge_bin", "./checksum.py"],
    outs=["snes.img"],
    commands=[
        "cp {ins[0]} {outs[0]}",
        "truncate -s %d {outs[0]}" % (2048 * 1024),
        "chronic python3 {ins[1]} HIROM {outs[0]}",
    ],
    label="MKCARTRIDGE",
)
