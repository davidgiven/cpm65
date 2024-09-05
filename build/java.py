from build.ab import (
    simplerule,
    Rule,
    Targets,
    TargetsMap,
    filenamesof,
    error,
    filenameof,
    emit,
)
from build.utils import targetswithtraitsof, collectattrs
from os.path import *

emit(
    """
JAR ?= jar
JAVAC ?= javac
JFLAGS ?= -g
"""
)


@Rule
def jar(self, name, srcs: Targets = [], srcroot=None):
    if not srcroot:
        srcroot = self.cwd
    fs = filenamesof(srcs)
    try:
        fs = [relpath(f, srcroot) for f in fs]
    except ValueError:
        error(f"some source files in {fs} aren't in the srcroot, {srcroot}")

    simplerule(
        replaces=self,
        ins=srcs,
        outs=["=source.jar"],
        commands=["jar cf {outs[0]} -C " + srcroot + " " + (" ".join(fs))],
        label="JAR",
    )


@Rule
def externaljar(self, name, path):
    simplerule(
        replaces=self,
        ins=[],
        outs=[],
        commands=[],
        label="EXTERNALJAR",
        jar=path,
    )


@Rule
def javalibrary(
    self,
    name,
    srcs: Targets = [],
    srcroot=None,
    extrasrcs: TargetsMap = {},
    deps: Targets = [],
):
    filemap = {k: filenameof(v) for k, v in extrasrcs.items()}
    ins = []
    for f in filenamesof(srcs):
        try:
            ff = relpath(f, srcroot)
        except ValueError:
            error(f"source file {f} is not in the srcroot {srcroot}")
        filemap[ff] = f
        ins += [f]

    jardeps = filenamesof(targetswithtraitsof(deps, "javalibrary")) + [
        t.args["jar"] for t in targetswithtraitsof(deps, "externaljar")
    ]

    dirs = {dirname(s) for s in filemap.keys()}
    cs = (
        [
            "rm -rf {dir}/srcs {dir}/objs {outs[0]}",
            "mkdir -p " + (" ".join([f"{self.dir}/srcs/{k}" for k in dirs])),
        ]
        + [f"cp {v} {self.dir}/srcs/{k}" for k, v in filemap.items()]
        + [
            " ".join(
                [
                    "$(JAVAC)",
                    "$(JFLAGS)",
                    "-d {dir}/objs",
                    " -cp " + (":".join(jardeps)) if jardeps else "",
                ]
                + [f"{self.dir}/srcs/{k}" for k in filemap.keys()]
            ),
            "$(JAR) --create --no-compress --file {outs[0]} -C {self.dir}/objs .",
        ]
    )

    simplerule(
        replaces=self,
        ins=ins + deps,
        outs=[f"={name}.jar"],
        commands=cs,
        label="JAVALIBRARY",
    )


@Rule
def javaprogram(
    self,
    name,
    srcs: Targets = [],
    srcroot=None,
    extrasrcs: TargetsMap = {},
    deps: Targets = [],
    mainclass=None,
):
    jars = filenamesof(targetswithtraitsof(deps, "javalibrary"))

    assert mainclass, "a main class must be specified for javaprogram"
    if srcs or extrasrcs:
        j = javalibrary(
            name=name + "_mainlib",
            srcs=srcs,
            srcroot=srcroot,
            extrasrcs=extrasrcs,
            deps=deps,
            cwd=self.cwd,
        )
        j.materialise()
        jars += [filenameof(j)]

    simplerule(
        replaces=self,
        ins=jars,
        outs=[f"={self.localname}.jar"],
        commands=["rm -rf {dir}/objs", "mkdir -p {dir}/objs"]
        + ["(cd {dir}/objs && $(JAR) xf $(abspath " + j + "))" for j in jars]
        + [
            "$(JAR) --create --file={outs[0]} --main-class="
            + mainclass
            + " -C {dir}/objs ."
        ],
        label="MERGEJARS",
    )
