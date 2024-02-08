from build.ab import normalrule, TargetsMap, filenameof, Rule
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
    cs = ["rm -f {outs[0]}"]
    ins = []

    cmd = "chronic cc1541 -q "
    if id:
        cmd += "-i %d " % id
    cmd += '-n "%s" {outs[0]}' % title
    cs += [cmd]

    for k, v in items.items():
        cs += [
            "chronic cc1541 -q -t -u 0 -r 18 -f %s -w %s {outs[0]}"
            % (k, filenameof(v))
        ]
        ins += [v]

    cs += ["{deps[0]} -f {outs[0]}"]
    normalrule(
        replaces=self,
        ins=ins,
        outs=[name + ".img"],
        deps=["tools+mkcombifs"],
        commands=cs,
        label="MKCBMFS",
    )


llvmclibrary(
    name="commodore_lib", srcs=["./ieee488.S", "./petscii.S"], deps=["include"]
)

llvmrawprogram(
    name="pet4032_bios",
    srcs=["./pet.S"],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DPET4032"],
    ldflags=["--no-check-sections"],
    linkscript="./pet.ld",
)

llvmrawprogram(
    name="pet8032_bios",
    srcs=["./pet.S"],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DPET8032"],
    ldflags=["--no-check-sections"],
    linkscript="./pet.ld",
)

llvmrawprogram(
    name="pet8096_bios",
    srcs=["./pet.S"],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    cflags=["-DPET8096"],
    ldflags=["--no-check-sections"],
    linkscript="./pet8096.ld",
)

llvmrawprogram(
    name="c64_bios",
    srcs=["./c64.S"],
    deps=["src/lib+bioslib", "include", ".+commodore_lib"],
    linkscript="./c64.ld",
)

llvmrawprogram(
    name="vic20_bios",
    srcs=["./vic20.S"],
    deps=[
        ".+commodore_lib",
        "include",
        "src/lib+bioslib",
        "third_party/tomsfonts+4x8",
    ],
    linkscript="./vic20.ld",
)

for target in ["c64", "pet4032", "pet8032", "pet8096", "vic20"]:
    mkcbmfs(
        name=target + "_cbmfs",
        title="cp/m-65: %s" % target,
        items={"cpm": ".+%s_bios" % target},
    )

for target in ["pet4032", "pet8032", "pet8096"]:
    mkcpmfs(
        name=target + "_diskimage",
        format="c1541",
        template=".+%s_cbmfs" % target,
        items=COMMODORE_ITEMS_WITH_SCREEN,
    )

for target in ["c64", "vic20"]:
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
    script="./mame-test.lua",
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
