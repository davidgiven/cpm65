from tools.build import mkcpmfs, shuffle, mametest
from build.llvm import llvmrawprogram, llvmcfile
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
    BIG_SCREEN_APPS,
    PASCAL_APPS,
)

llvmcfile(
    name="bios_obj",
    srcs=["./apple2e.S"],
    cflags=["-DAPPLE2E"],
#    cflags=["-DAPPLE2PLUS"],
    deps=["include", "src/lib+bioslib"],
)

llvmrawprogram(
    name="bios_prelink",
    srcs=[".+bios_obj"],
    deps=["src/lib+bioslib"],
    cflags=["-DAPPLE2E"],
#    cflags=["-DAPPLE2PLUS"],
    linkscript="./apple2e-prelink.ld",
    ldflags=["--defsym=BIOS_SIZE=0x4000"],
)

llvmrawprogram(
    name="bios",
    srcs=[".+bios_obj"],
    deps=[
        ".+bios_prelink",
        "scripts/size.awk",
        "src/lib+bioslib",
    ],
    linkscript="./apple2e.ld",
    ldflags=[
        "--defsym=BIOS_SIZE=$$($(LLVM)/llvm-objdump --section-headers {deps[0]} "
        + "| gawk --non-decimal-data -f scripts/size.awk)"
    ],
)

shuffle(
    name="bios_shuffled",
    src=".+bios",
    blocksize=256,
    blockspertrack=16,
    map="02468ace13579bdf",
)

mkcpmfs(
    name="diskimage",
    format="appleiie",
    bootimage=".+bios_shuffled",
    size=143360,
    items={
        "0:ccp.sys@sr": "src+ccp-tiny",
        "0:bdos.sys@sr": "src/bdos",
        "0:cls.com": "apps+cls",
        "0:atbasic.com": "third_party/altirrabasic",
        "0:atbasic.txt": "cpmfs+atbasic_txt_cpm",
        "0:qe.com": "apps+qe",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS,
)

mkcpmfs(
    name="diskimage_b",
    format="appleiie",
    bootimage=".+bios_shuffled",
    size=143360,
    items={
    }
    | SCREEN_APPS
    | SCREEN_APPS_SRCS
    | BIG_SCREEN_APPS
    | PASCAL_APPS,
)


mametest(
    name="mametest",
    target="apple2e",
    diskimage=".+diskimage",
    imagetype=".po",
    script="./mame-test.lua",
)
