from tools.build import mkcpmfs, shuffle, mametest
from build.llvm import llvmrawprogram, llvmcfile
from build.zip import zip
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    CPM_FILESYSTEM_APP_NAMES,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
    PASCAL_APPS,
)
import re

llvmcfile(
    name="bios_obj",
    srcs=["./neo6502.S"],
    deps=["include", "src/lib+bioslib", "src/bdos+bdoslib"],
    cflags=[
        "-mcpu=mosw65c02",
    ],
)

llvmrawprogram(
    name="bios_prelink",
    srcs=[".+bios_obj"],
    deps=[
        "src/lib+bioslib",
        "src/bdos+bdoslib",
        "./neo6502-common.ld",
    ],
    linkscript="./neo6502-prelink.ld",
    ldflags=["--defsym=BIOS_SIZE=0x4000"],
)

llvmrawprogram(
    name="bios",
    srcs=[".+bios_obj"],
    deps=[
        ".+bios_prelink",
        "scripts/size.awk",
        "src/lib+bioslib",
        "src/bdos+bdoslib",
        "./neo6502-common.ld",
    ],
    linkscript="./neo6502.ld",
    ldflags=[
        "--defsym=BIOS_SIZE=$$($(LLVM)/llvm-objdump --section-headers {deps[0]} "
        + "| gawk --non-decimal-data -f scripts/size.awk)"
    ],
)

zip(
    name="diskimage",
    items={
        "CPM65.NEO": ".+bios",
        "A/CCP.SYS": "src+ccp",
        "B/NCOPY.COM": "src/arch/neo6502/utils+ncopy",
        "B/NATTR.COM": "src/arch/neo6502/utils+nattr",
        "B/NDIR.COM": "src/arch/neo6502/utils+ndir",
        "B/NTRUNC.COM": "src/arch/neo6502/utils+ntrunc",
    }
    | {
        re.sub("^0:", "A/", k).upper(): v
        for k, v in (
            {
                k: v
                for k, v in MINIMAL_APPS.items()
                if k not in CPM_FILESYSTEM_APP_NAMES
            }
            | MINIMAL_APPS_SRCS
            | BIG_APPS
            | BIG_APPS_SRCS
            | SCREEN_APPS
            | SCREEN_APPS_SRCS
            | PASCAL_APPS
        ).items()
    },
)
