from build.ab import Rule, Target, normalrule, filenameof, targetsof, TargetsMap
from build.c import cxxprogram, cprogram

cxxprogram(name="multilink", srcs=["./multilink.cc"], deps=["+libfmt"])

cxxprogram(name="xextobin", srcs=["./xextobin.cc"], deps=["+libfmt"])

cprogram(name="mkdfs", srcs=["./mkdfs.c"], deps=["+libfmt"])


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


@Rule
def mkcpmfs(self, name, format, items: TargetsMap = {}):
    cs = ["mkfs.cpm -f %s {outs[0]}" % format]
    ins = []
    for k, v in items.items():
        cs += ["cpmcp -f %s {outs[0]} %s %s" % (format, filenameof(v), k)]
        ins += [v]

    normalrule(
        replaces=self,
        ins=ins,
        outs=[name + ".img"],
        deps=["diskdefs"],
        commands=cs,
        label="MKCPMFS",
    )


@Rule
def mkdfs(
    self, name=None, out=None, title="DFS", opt=0, items: TargetsMap = {}
):
    cs = []
    ins = []
    for k, v in items.items():
        if type(k) == str:
            k = {"name": k}

        ins += [v]
        cs += ["-f", filenameof(v), "-n", k["name"]]
        if "loadaddr" in k:
            cs += ["-l", k["loadaddr"]]
        if "execaddr" in k:
            cs += ["-e", k["execaddr"]]

    normalrule(
        replaces=self,
        ins=ins,
        outs=[out],
        deps=["tools+mkdfs"],
        commands=[
            ("{deps[0]} -O {outs[0]} -B %d -N %s " % (opt, title))
            + " ".join(cs)
        ],
        label="MKDFS",
    )
