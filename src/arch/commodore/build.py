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
def mkcbmfs(
    self, name, items: TargetsMap = {}, type="d64", title="CBMFS", id=""
):
    cs = []
    ins = []
    deps = ["tools+mkcombifs"]

    if type == "d2m":
        cs += [f"zcat $[deps[1]] > $[outs[0]]"]
        deps += ["extras/empty.d2m.gz"]
    else:
        cs += [f"chronic c1541 -format '{title}',{id} {type} $[outs[0]]"]

    cmd = f"chronic c1541 $[outs[0]] -name '{title}'"
    for k, v in items.items():
        t = "p"
        if k.startswith("&"):
            t = "u"

        cmd += f" -write '{filenameof(v)}' '{k},{t}'"
        ins += [v]
    cs += [cmd]

    if type != "d2m":
        cs += ["$[deps[0]] -f $[outs[0]]"]
    simplerule(
        replaces=self,
        ins=ins,
        outs=[f"={name}.{type}"],
        deps=deps,
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
    name="vic20_yload_loader",
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
    name="vic20_iec_loader",
    srcs=[
        "./vic20/vic20loader_iec.S",
        "./vic20/vic20.inc",
    ],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DVIC20"],
    linkscript="./vic20/vic20loader.ld",
)

llvmrawprogram(
    name="vic20_yload_1541_bios",
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
    ldflags=["--gc-sections"],
    linkscript="./vic20/vic20.ld",
)

llvmrawprogram(
    name="vic20_iec_1541_bios",
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
    ldflags=["--gc-sections"],
    linkscript="./vic20/vic20.ld",
)

llvmrawprogram(
    name="vic20_iec_fd2000_bios",
    srcs=[
        "./vic20/vic20.S",
        "./diskaccess/bios_fd2000.S",
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
    ldflags=["--gc-sections"],
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
    name="vic20_yload_1541_cbmfs",
    title="cp/m-65: vic20",
    items={
        "cpm": ".+vic20_yload_loader",
        "&yload1541": ".+usr_yload1541",
        "bios": ".+vic20_yload_1541_bios",
    },
)

mkcbmfs(
    name="vic20_iec_1541_cbmfs",
    title="cp/m-65: vic20",
    items={
        "cpm": ".+vic20_iec_loader",
        "bios": ".+vic20_iec_1541_bios",
    },
)

mkcbmfs(
    name="vic20_iec_fd2000_cbmfs",
    title="cp/m-65: vic20",
    type="d2m",
    items={
        "cpm": ".+vic20_iec_loader",
        "bios": ".+vic20_iec_fd2000_bios",
    },
)

for target in ["pet4032", "pet8032", "pet8096"]:
    mkcbmfs(
        name=target + "_cbmfs",
        title="cp/m-65: %s" % target,
        items={"cpm": ".+%s_bios" % target},
    )

for target in [
    "pet4032",
    "pet8032",
    "pet8096",
    "c64",
    "vic20_yload_1541",
    "vic20_iec_1541",
]:
    mkcpmfs(
        name=target + "_diskimage",
        format="c1541",
        template=".+%s_cbmfs" % target,
        items=COMMODORE_ITEMS_WITH_SCREEN,
    )

mkcpmfs(
    name="vic20_iec_fd2000_diskimage",
    format="fd2000",
    template=".+vic20_iec_fd2000_cbmfs",
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
