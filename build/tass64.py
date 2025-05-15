from build.ab import simplerule, Targets, Rule
from build.utils import filenamesof
from os.path import *


@Rule
def tass64(self, name, srcs: Targets, deps: Targets = [], flags=[]):
    srcfile = None
    incfiles = []
    incdirs = set()
    for f in filenamesof(srcs):
        if f.endswith(".asm"):
            assert not srcfile, "you can only specify one source .asm file"
            srcfile = f
        else:
            incfiles += [f]
            incdirs.add(dirname(f))
    incdirs = " ".join([f"-I{f}" for f in sorted(incdirs)])

    simplerule(
        replaces=self,
        ins=[srcfile],
        deps=incfiles + deps,
        outs=[f"={self.localname}.bin"],
        commands=[
            f"64tass --quiet $[flags] {incdirs} --list $[outs[0]].lst -o $[outs[0]] $[ins[0]]"
        ],
        label="64TASS",
    )
