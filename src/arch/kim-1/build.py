from tools.build import mkimd, mkcpmfs
from build.llvm import llvmrawprogram, llvmclibrary
from build.zip import zip
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    PASCAL_APPS,
)

llvmclibrary(
    name="libsd", srcs=["./libsd.S"], cflags=["-I ."], deps=["include"]
)

llvmclibrary(
    name="k-1013", srcs=["./k-1013.S"], cflags=["-I ."], deps=["include"]
)

llvmrawprogram(
    name="bios-k1013",
    srcs=["./kim-1-k1013.S"],
    deps=["./kim-1.S", "./kim-1.inc", "include", "src/lib+bioslib", ".+k-1013"],
    linkscript="./kim-1-k1013.ld",
)

llvmrawprogram(
    name="bios-sdcard",
    srcs=["./kim-1-sdcard.S"],
    deps=["./kim-1.S", "./kim-1.inc", "include", "src/lib+bioslib", ".+libsd"],
    linkscript="./kim-1-sdcard.ld",
)

mkcpmfs(
    name="rawdiskimage-k1013",
    format="k-1013",
    bootimage=".+bios-k1013",
    size=256 * 77 * 26,
    items={"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | {"0:pasc.pas": "third_party/pascal-m+pasc_pas_cpm"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

mkcpmfs(
    name="rawdiskimage-sdcard",
    format="sdcard",
    bootimage=".+bios-sdcard",
    size=512 * 4096 * 16,
    items={"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | {"0:pasc.pas": "third_party/pascal-m+pasc_pas_cpm"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

mkimd(name="diskimage-k1013", src=".+rawdiskimage-k1013")

zip(
    name="distro-k1013",
    items={
        "diskimage.imd": ".+diskimage-k1013",
        "boot.bin": "src/arch/kim-1/boot+boot.bin",
        "boot.pap": "src/arch/kim-1/boot+boot.pap",
    },
)

zip(
    name="distro-sdcard",
    items={
        "diskimage.raw": ".+rawdiskimage-sdcard",
        "bootsd.bin": "src/arch/kim-1/boot+bootsd.bin",
        "bootsd.pap": "src/arch/kim-1/boot+bootsd.pap",
        "bootsd-kimrom.bin": "src/arch/kim-1/boot+bootsd-kimrom.bin",
    },
)

