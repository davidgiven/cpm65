from build.ab import Rule, Target, normalrule
from build.llvm import llvmrawprogram

@Rule
def mkpap(self, name, src: Target = None):
    normalrule(
        replaces=self,
        ins=[src],
        outs=[name],
        commands=["srec_cat {ins[0]} -binary -offset 0x0200 -o {outs[0]} -MOS_Technologies"],
        label="SREC",
    )

llvmrawprogram (
    name="boot.bin",
    srcs=["./boot.S"],
    linkscript="./boot.ld",
)

llvmrawprogram (
    name="bootsd.bin",
    srcs=["./bootsd.S"],
    linkscript="./boot.ld",
)

mkpap(name="boot.pap", src=".+boot.bin")

mkpap(name="bootsd.pap", src=".+bootsd.bin")
