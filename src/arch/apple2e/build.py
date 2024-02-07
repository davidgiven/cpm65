from tools.build import mkcpmfs, shuffle, mametest
from build.llvm import llvmrawprogram, llvmcfile
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
)

llvmcfile(
    name="bios_obj",
    srcs=["./apple2e.S"],
    deps=["include", "src/lib+bioslib"],
)

llvmrawprogram(
    name="bios_prelink",
    srcs=[".+bios_obj"],
    deps=["src/lib+bioslib"],
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
    items={"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS,
)

mametest(
    name="mametest",
    target="apple2e",
    diskimage=".+diskimage",
    imagetype=".po",
    script="./mame-test.lua",
)
