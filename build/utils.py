from build.ab import Rule, simplerule, Target, filenameof, Targets, filenamesof
from os.path import basename, splitext
import fnmatch
import itertools


def filenamesmatchingof(xs, pattern):
    return fnmatch.filter(filenamesof(xs), pattern)


def stripext(path):
    return splitext(path)[0]


def targetswithtraitsof(xs, trait):
    return [t for t in xs if trait in t.traits]


def collectattrs(*, targets, name, initial=[]):
    s = set(initial)
    for a in [t.args.get(name, []) for t in targets]:
        s.update(a)
    return s


@Rule
def objectify(self, name, src: Target, symbol):
    simplerule(
        replaces=self,
        ins=["build/_objectify.py", src],
        outs=[f"={basename(filenameof(src))}.h"],
        commands=["$(PYTHON) {ins[0]} {ins[1]} " + symbol + " > {outs}"],
        label="OBJECTIFY",
    )


@Rule
def test(
    self,
    name,
    command: Target = None,
    commands=None,
    ins: Targets = None,
    deps: Targets = None,
    label="TEST",
):
    if command:
        simplerule(
            replaces=self,
            ins=[command],
            outs=["sentinel"],
            commands=["{ins[0]}", "touch {outs}"],
            deps=deps,
            label=label,
        )
    else:
        simplerule(
            replaces=self,
            ins=ins,
            outs=["sentinel"],
            commands=commands + ["touch {outs}"],
            deps=deps,
            label=label,
        )
