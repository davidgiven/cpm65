from build.ab import normalrule, emit, Rule, Targets, Target

emit("FPC ?= fpc")

normalrule(
    name="mads",
    ins=["./mads.pas"],
    outs=["mads"],
    commands=["$(FPC) -Mdelphi -v0 -Os {ins[0]} -o{outs[0]}"],
    label="FREEPASCAL",
)


@Rule
def mads(self, name=None, src: Target = None, deps: Targets = [], defines={}):
    ds = [f"-d:{k}={v}" for k, v in defines.items()]

    normalrule(
        replaces=self,
        ins=[src],
        outs=[name + ".bin"],
        deps=["third_party/mads"] + deps,
        commands=["{deps[0]} {ins[0]} -c -o:{outs[0]} " + " ".join(ds)],
        label="MADS",
    )
