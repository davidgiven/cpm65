from build.ab import Rule, Target, normalrule
from build.c import cxxprogram

cxxprogram(name="multilink", srcs=["./multilink.cc"], deps=["+libfmt"])

cxxprogram(name="xextobin", srcs=["./xextobin.cc"], deps=["+libfmt"])


@Rule
def multilink(
    self, name=None, core: Target = None, zp: Target = None, tpa: Target = None
):
    normalrule(
        replaces=self,
        ins=[core, zp, tpa],
        outs=[name + ".com"],
        deps=["tools+multilink"],
        commands=["{deps[0]} -o {outs[0]} {ins}"],
        label="MULTILINK",
    )


@Rule
def xextobin(self, name=None, src: Target = None, address=0):
    normalrule(
        replaces=self,
        ins=[src],
        outs=[name + ".bin"],
        deps=["tools+xextobin"],
        commands=["{deps[0]} -i {ins[0]} -o {outs[0]} -b %d" % address],
        label="XEXTOBIN",
    )
