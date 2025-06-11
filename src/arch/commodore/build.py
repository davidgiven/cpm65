from build.ab import simplerule, TargetsMap, filenameof, Rule, Target
from tools.build import mkcpmfs, mametest
from build.llvm import llvmrawprogram, llvmclibrary
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    SCREEN_APPS,
    SCREEN_APPS_SRCS,
)

COMMODORE_ITEMS = (
    {"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
)

COMMODORE_ITEMS_WITH_SCREEN = COMMODORE_ITEMS | SCREEN_APPS | SCREEN_APPS_SRCS


@Rule
def mkcbmfs(self, name, items: TargetsMap = {}, title="CBMFS", id=None):
    cs = ["rm -f $[outs[0]]"]
    ins = []

    cmd = "chronic cc1541 -q "
    if id:
        cmd += "-i %d " % id
    cmd += '-n "%s" $[outs[0]]' % title
    cs += [cmd]

    for k, v in items.items():
        t = "PRG"
        if k.startswith("&"):
            t = "USR"

        cs += [
            "chronic cc1541 -q -t -u 0 -r 18 -f '%s' -T '%s' -w '%s' $[outs[0]]"
            % (k, t, filenameof(v))
        ]
        ins += [v]

    cs += ["$[deps[0]] -f $[outs[0]]"]
    simplerule(
        replaces=self,
        ins=ins,
        outs=[f"={name}.img"],
        deps=["tools+mkcombifs"],
        commands=cs,
        label="MKCBMFS",
    )


@Rule
def mkusr(self, name, src: Target):
    simplerule(
        replaces=self,
        ins=["tools+mkusr", src],
        outs=[f"={self.localname}.usr"],
        commands=["chronic $[ins[0]] -r $[ins[1]] -w $[outs[0]]"],
        label="MKUSR",
    )


llvmclibrary(
    name="commodore_lib",
    srcs=["./common/genericdisk.S", "./common/petscii.S"],
    deps=["include"],
)

llvmrawprogram(
    name="pet4032_bios",
    srcs=[
        "./pet.S",
        "./diskaccess/bios_1541.S",
        "./diskaccess/io_ieee488.S",
        "./diskaccess/rw_ieee488.S",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DPET4032"],
    ldflags=["--no-check-sections"],
    linkscript="./pet.ld",
)

llvmrawprogram(
    name="pet8032_bios",
    srcs=[
        "./pet.S",
        "./diskaccess/bios_1541.S",
        "./diskaccess/io_ieee488.S",
        "./diskaccess/rw_ieee488.S",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DPET8032"],
    ldflags=["--no-check-sections"],
    linkscript="./pet.ld",
)

llvmrawprogram(
    name="pet8096_bios",
    srcs=[
        "./pet.S",
        "./diskaccess/bios_1541.S",
        "./diskaccess/io_ieee488.S",
        "./diskaccess/rw_ieee488.S",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DPET8096"],
    ldflags=["--no-check-sections"],
    linkscript="./pet8096.ld",
)

llvmrawprogram(
    name="elf_yload1541",
    srcs=["./diskaccess/yload1541.S"],
    deps=["include"],
    linkscript="./diskaccess/yload1541.ld",
)

mkusr(name="usr_yload1541", src=".+elf_yload1541")

llvmrawprogram(
    name="c64_loader",
    srcs=[
        "./c64/c64loader.S",
        "./diskaccess/io_yload_c64.S",
        "./diskaccess/io_yload_common.S",
        "./c64/c64.inc",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DC64"],
    linkscript="./c64/c64loader.ld",
)

llvmrawprogram(
    name="c64_bios",
    srcs=[
        "./c64/c64.S",
        "./diskaccess/bios_1541.S",
        "./diskaccess/io_yload_c64.S",
        "./diskaccess/rw_yload.S",
        "./c64/c64.inc",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DC64"],
    linkscript="./c64/c64.ld",
)

llvmrawprogram(
    name="vic20_loader",
    srcs=[
        "./vic20/vic20loader.S",
        "./diskaccess/io_yload_vic20.S",
        "./diskaccess/io_yload_common.S",
        "./vic20/vic20.inc",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DVIC20"],
    linkscript="./vic20/vic20loader.ld",
)

llvmrawprogram(
    name="vic20_loader_iec",
    srcs=[
        "./vic20/vic20loader_iec.S",
        "./vic20/vic20.inc",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DVIC20"],
    linkscript="./vic20/vic20loader.ld",
)

llvmrawprogram(
    name="vic20_bios",
    srcs=[
        "./vic20/vic20.S",
        "./diskaccess/bios_1541.S",
        "./diskaccess/io_yload_vic20.S",
        "./diskaccess/rw_yload.S",
        "./vic20/vic20.inc",
    ],
    deps=[
        "include",
        "src/lib+bioslib",
        "third_party/tomsfonts+4x8",
        ".+commodore_lib",
    ],
    cflags=["-DVIC20"],
    linkscript="./vic20/vic20.ld",
)

llvmrawprogram(
    name="vic20_bios_iec",
    srcs=[
        "./vic20/vic20.S",
        "./diskaccess/bios_1541.S",
        "./diskaccess/io_ieee488.S",
        "./diskaccess/io_ieee488_vic20.S",
        "./diskaccess/rw_ieee488.S",
        "./vic20/vic20.inc",
    ],
    deps=[
        "include",
        "src/lib+bioslib",
        "third_party/tomsfonts+4x8",
        ".+commodore_lib",
    ],
    cflags=["-DVIC20"],
    linkscript="./vic20/vic20.ld",
)

mkcbmfs(
    name="c64_cbmfs",
    title="cp/m-65: c64",
    items={
        "cpm": ".+c64_loader",
        "&yload1541": ".+usr_yload1541",
        "bios": ".+c64_bios",
    },
)

mkcbmfs(
    name="vic20_cbmfs",
    title="cp/m-65: vic20",
    items={
        "cpm": ".+vic20_loader",
        "&yload1541": ".+usr_yload1541",
        "bios": ".+vic20_bios",
    },
)

mkcbmfs(
    name="vic20_iec_cbmfs",
    title="cp/m-65: vic20",
    items={
        "cpm": ".+vic20_loader_iec",
        "bios": ".+vic20_bios_iec",
    },
)

for target in ["pet4032", "pet8032", "pet8096"]:
    mkcbmfs(
        name=target + "_cbmfs",
        title="cp/m-65: %s" % target,
        items={"cpm": ".+%s_bios" % target},
    )

for target in ["pet4032", "pet8032", "pet8096", "c64", "vic20", "vic20_iec"]:
    mkcpmfs(
        name=target + "_diskimage",
        format="c1541",
        template=".+%s_cbmfs" % target,
        items=COMMODORE_ITEMS_WITH_SCREEN,
    )

mametest(
    name="c64_mametest",
    target="c64",
    diskimage=".+c64_diskimage",
    imagetype=".d64",
    script="./c64/c64-mame-test.lua",
)

mametest(
    name="pet4032_mametest",
    target="pet4032",
    diskimage=".+pet4032_diskimage",
    imagetype=".d64",
    runscript="./pet-mame-test.sh",
    script="./pet-mame-test.lua",
)

mametest(
    name="pet8032_mametest",
    target="pet8032",
    diskimage=".+pet8032_diskimage",
    imagetype=".d64",
    runscript="./pet-mame-test.sh",
    script="./pet-mame-test.lua",
)
