from build.ab import normalrule
from tools.build import mkdfs, mkcpmfs
from build.llvm import llvmrawprogram

llvmrawprogram(
    name="bios",
    srcs=["./bbcmicro.S", "./mos.inc"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./bbcmicro.ld",
)

mkcpmfs(name="cpmfs", format="bbc192", items={"0:ccp.sys": "src+ccp"})

mkdfs(
    name="diskimage",
    out="bbcmicro.ssd",
    title="CP/M-65",
    opt=2,
    items={
        "!boot@0x0400": ".+bios",
        "bdos": "src+bdos",
        "cpmfs": ".+cpmfs",
    },
)
