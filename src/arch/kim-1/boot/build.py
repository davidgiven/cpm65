from build.ab import Rule, Target, simplerule
from build.llvm import llvmrawprogram


@Rule
def mkpap(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}"],
        commands=[
            "srec_cat $[ins[0]] -binary -offset 0x0200 -o $[outs[0]] -MOS_Technologies"
        ],
        label="SREC",
    )

llvmrawprogram(
    name="boot.bin",
    srcs=["./boot.S"],
    linkscript="./boot.ld",
)

llvmrawprogram(
    name="bootsd.bin",
    srcs=["./bootsd.S"],
    linkscript="./boot.ld",
)

llvmrawprogram(
    name="bootsd-kimrom.bin",
    srcs=["./bootsd.S"],
    cflags=["-DKIM_ROM"],
    linkscript="./boot-kimrom.ld",
)

llvmrawprogram(
    name="bootiec-kim.bin",
    srcs=["./bootiec.S"],
    linkscript="./boot.ld",
)

llvmrawprogram(
    name="bootiec-pal.bin",
    srcs=["./bootiec.S"],
    cflags=["-DPAL_1"],
    linkscript="./boot.ld",
)

llvmrawprogram(
    name="bootsdshield.bin",
    srcs=["./bootsdshield.S"],
    linkscript="./boot.ld",
)

llvmrawprogram(
    name="bootsdshield-kimrom.bin",
    srcs=["./bootsdshield.S"],
    cflags=["-DKIM_ROM"],
    linkscript="./boot-kimrom.ld",
)

mkpap(name="boot.pap", src=".+boot.bin")

mkpap(name="bootsd.pap", src=".+bootsd.bin")

mkpap(name="bootiec-kim.pap", src=".+bootiec-kim.bin")

mkpap(name="bootiec-pal.pap", src=".+bootiec-pal.bin")

mkpap(name="bootsdshield.pap", src=".+bootsdshield.bin")
