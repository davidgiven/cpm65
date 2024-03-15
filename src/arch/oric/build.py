from tools.build import mkcpmfs, mkoricdsk, mametest
from build.llvm import llvmrawprogram, llvmcfile
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
    PASCAL_APPS,
)

llvmcfile(
    name="bios_obj",
    srcs=["./oric.S"],
    deps=["include", "src/lib+bioslib"],
)

llvmrawprogram(
    name="bios_prelink",
    srcs=[".+bios_obj"],
    deps=["src/lib+bioslib", "./oric-common.ld"],
    linkscript="./oric-prelink.ld",
    ldflags=["--defsym=BIOS_SIZE=0x4000"],
)

llvmrawprogram(
    name="bios",
    srcs=[".+bios_obj"],
    deps=[
        ".+bios_prelink",
        "scripts/size.awk",
        "src/lib+bioslib",
        "./oric-common.ld",
    ],
    linkscript="./oric.ld",
    ldflags=[
        "--defsym=BIOS_SIZE=$$($(LLVM)/llvm-objdump --section-headers {deps[0]} "
        + "| gawk --non-decimal-data -f scripts/size.awk)"
    ],
)

mkcpmfs(
    name="cpmfs",
    format="oric",
    bootimage=".+bios",
    items={"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | SCREEN_APPS
    | SCREEN_APPS_SRCS
    | PASCAL_APPS,
)

mkoricdsk(name="diskimage", src=".+cpmfs")

mametest(
    name="mametest",
    target="oric1",
    runscript="scripts/oric-mame-test.sh",
    diskimage=".+diskimage",
    imagetype=".dsk",
    script="./mame-test.lua",
)
