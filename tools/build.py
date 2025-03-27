from build.ab import (
    Rule,
    Target,
    simplerule,
    filenameof,
    TargetsMap,
    filenamesof,
)
from build.c import cxxprogram, cprogram

cxxprogram(name="multilink", srcs=["./multilink.cc"], deps=["+libfmt"])
cxxprogram(name="xextobin", srcs=["./xextobin.cc"], deps=["+libfmt"])
cxxprogram(name="shuffle", srcs=["./shuffle.cc"], deps=["+libfmt"])
cxxprogram(name="mkoricdsk", srcs=["./mkoricdsk.cc"], deps=["+libfmt"])
cxxprogram(name="mkcombifs", srcs=["./mkcombifs.cc"], deps=["+libfmt"])
cxxprogram(name="fillfile", srcs=["./fillfile.cc"], deps=["+libfmt"])
cprogram(name="unixtocpm", srcs=["./unixtocpm.c"])
cprogram(name="mkdfs", srcs=["./mkdfs.c"])
cprogram(name="mkimd", srcs=["./mkimd.c"])
cprogram(
    name="fontconvert", srcs=["./fontconvert.c", "./libbdf.c", "./libbdf.h"]
)
cprogram(name="img2osi", srcs=["./img2osi.c", "./osi.h"])


@Rule
def unixtocpm(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.txt"],
        deps=["tools+unixtocpm"],
        commands=["$[deps[0]] < $[ins[0]] > $[outs[0]]"],
        label="UNIXTOCPM",
    )


@Rule
def multilink(
    self, name=None, core: Target = None, zp: Target = None, tpa: Target = None
):
    simplerule(
        replaces=self,
        ins=[core, zp, tpa],
        outs=[f"={name}.com"],
        deps=["tools+multilink"],
        commands=["$[deps[0]] -o $[outs[0]] $[ins]"],
        label="MULTILINK",
    )


@Rule
def xextobin(self, name=None, src: Target = None, address=0):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.bin"],
        deps=["tools+xextobin"],
        commands=["$[deps[0]] -i $[ins[0]] -o $[outs[0]] -b %d" % address],
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
        cs += ["cp %s $[outs[0]]" % filenameof(template)]
    else:
        # Some versions of mkfs.cpm don't work right if the input file
        # doesn't exist.
        cs += ["$[deps[1]] -f $[outs[0]] -b 0xe5 -n 100000"]
        mkfs = "mkfs.cpm -f %s" % format
        if bootimage:
            mkfs += " -b %s" % filenameof(bootimage)
        mkfs += " $[outs[0]]"
        cs += [mkfs]

    ins = []
    for k, v in items.items():
        flags = None
        if "@" in k:
            k, flags = k.split("@")

        cs += ["cpmcp -f %s $[outs[0]] %s %s" % (format, filenameof(v), k)]
        if flags:
            cs += ["cpmchattr -f %s $[outs[0]] %s %s" % (format, flags, k)]
        ins += [v]

    if size:
        cs += ["truncate -s %d $[outs[0]]" % size]

    simplerule(
        replaces=self,
        ins=ins,
        outs=[f"={name}.img"],
        deps=(
            ["diskdefs", "tools+fillfile"]
            + (
                [bootimage]
                if bootimage
                else [] + [template] if template else []
            )
        ),
        commands=cs,
        label="MKCPMFS",
    )


@Rule
def mkdfs(self, name, title="DFS", opt=0, items: TargetsMap = {}):
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

    simplerule(
        replaces=self,
        ins=ins,
        outs=["=dfs.ssd"],
        deps=["tools+mkdfs"],
        commands=[
            ("$[deps[0]] -O $[outs[0]] -B %d -N %s " % (opt, title))
            + " ".join(cs)
        ],
        label="MKDFS",
    )


@Rule
def shuffle(
    self, name, src: Target = None, blocksize=256, blockspertrack=16, map=""
):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.bin"],
        deps=["tools+shuffle"],
        commands=[
            "$[deps[0]] -i $[ins[0]] -o $[outs[0]] -b %d -t %d -r -m %s"
            % (blocksize, blockspertrack, map)
        ],
        label="SHUFFLE",
    )


@Rule
def fontconvert(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.inc"],
        deps=["tools+fontconvert"],
        commands=["$[deps[0]] $[ins[0]] > $[outs[0]]"],
        label="FONTCONVERT",
    )


@Rule
def mkoricdsk(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.img"],
        deps=["tools+mkoricdsk"],
        commands=["$[deps[0]] -i $[ins[0]] -o $[outs[0]]"],
        label="MKORICDSK",
    )


@Rule
def mkimd(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.imd"],
        deps=["tools+mkimd"],
        commands=["$[deps[0]] -i $[ins[0]] -o $[outs[0]]"],
        label="MKIMD",
    )


@Rule
def img2os5(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.os5"],
        deps=["tools+img2osi"],
        commands=["$[deps[0]] $[ins[0]] $[outs[0]]"],
        label="IMG2OS5",
    )


@Rule
def img2os8(self, name, src: Target = None):
    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.os8"],
        deps=["tools+img2osi"],
        commands=["$[deps[0]] $[ins[0]] $[outs[0]]"],
        label="IMG2OS8",
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
    simplerule(
        replaces=self,
        ins=[diskimage, script],
        outs=["=stamp"],
        deps=[runscript],
        commands=[
            "sh $[deps[0]] %s %s %s %s"
            % (target, filenameof(diskimage), filenameof(script), imagetype),
            "touch $[outs[0]]",
        ],
        label="MAMETEST",
    )
