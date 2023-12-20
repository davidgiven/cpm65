from build.ab import Rule, Target, normalrule, filenameof, targetsof, TargetsMap
from build.c import cxxprogram, cprogram

cxxprogram(name="multilink", srcs=["./multilink.cc"], deps=["+libfmt"])
cxxprogram(name="xextobin", srcs=["./xextobin.cc"], deps=["+libfmt"])
cxxprogram(name="shuffle", srcs=["./shuffle.cc"], deps=["+libfmt"])
cxxprogram(name="mkoricdsk", srcs=["./mkoricdsk.cc"], deps=["+libfmt"])
cxxprogram(name="mkcombifs", srcs=["./mkcombifs.cc"], deps=["+libfmt"])
cprogram(name="mkdfs", srcs=["./mkdfs.c"])
cprogram(
    name="fontconvert", srcs=["./fontconvert.c", "./libbdf.c", "./libbdf.h"]
)


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
def mkcpmfs(
    self,
    name,
    format,
    template: Target = None,
    bootimage: Target = None,
    size=None,
    items: TargetsMap = {},
):
    cs = []
    if template:
        cs += ["cp %s {outs[0]}" % filenameof(template)]
    else:
        mkfs = "mkfs.cpm -f %s" % format
        if bootimage:
            mkfs += " -b %s" % filenameof(bootimage)
        mkfs += " {outs[0]}"
        cs += [mkfs]

    ins = []
    for k, v in items.items():
        flags = None
        if "@" in k:
            k, flags = k.split("@")
        cs += ["cpmcp -f %s {outs[0]} %s %s" % (format, filenameof(v), k)]
        if flags:
            cs += ["cpmchattr -f %s {outs[0]} %s %s" % (format, flags, k)]
        ins += [v]

    if size:
        cs += ["truncate -s %d {outs[0]}" % size]

    normalrule(
        replaces=self,
        ins=ins,
        outs=[name + ".img"],
        deps=["diskdefs"] + [bootimage]
        if bootimage
        else [] + [template]
        if template
        else [],
        commands=cs,
        label="MKCPMFS",
    )


@Rule
def mkdfs(self, name, out=None, title="DFS", opt=0, items: TargetsMap = {}):
    cs = []
    ins = []
    for k, v in items.items():
        addr = None
        if "@" in k:
            k, addr = k.split("@")

        ins += [v]
        cs += ["-f", filenameof(v), "-n", k]
        if addr:
            cs += ["-l", addr, "-e", addr]

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


@Rule
def shuffle(
    self, name, src: Target = None, blocksize=256, blockspertrack=16, map=""
):
    normalrule(
        replaces=self,
        ins=[src],
        outs=[name + ".bin"],
        deps=["tools+shuffle"],
        commands=[
            "{deps[0]} -i {ins[0]} -o {outs[0]} -b %d -t %d -r -m %s"
            % (blocksize, blockspertrack, map)
        ],
        label="SHUFFLE",
    )


@Rule
def fontconvert(self, name, src: Target = None):
    normalrule(
        replaces=self,
        ins=[src],
        outs=[name + ".inc"],
        deps=["tools+fontconvert"],
        commands=["{deps[0]} {ins[0]} > {outs[0]}"],
        label="FONTCONVERT",
    )


@Rule
def mkoricdsk(self, name, src: Target = None):
    normalrule(
        replaces=self,
        ins=[src],
        outs=[name + ".img"],
        deps=["tools+mkoricdsk"],
        commands=["{deps[0]} -i {ins[0]} -o {outs[0]}"],
        label="MKORICDSK",
    )


@Rule
def mametest(
    self,
    name,
    target,
    runscript: Target = "scripts/mame-test.sh",
    diskimage: Target = None,
    imagetype=".img",
    script: Target = None,
):
    normalrule(
        replaces=self,
        ins=[diskimage, script],
        outs=["stamp"],
        deps=[runscript],
        commands=[
            "sh {deps[0]} %s %s %s %s"
            % (target, filenameof(diskimage), filenameof(script), imagetype),
            "touch {outs[0]}",
        ],
        label="MAMETEST",
    )
