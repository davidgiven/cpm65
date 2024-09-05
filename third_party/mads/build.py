from build.ab import simplerule, emit, Rule, Targets, Target

emit("FPC ?= fpc")

simplerule(
    name="mads",
    ins=["./mads.pas"],
    outs=["=mads"],
    commands=["chronic $(FPC) -Mdelphi -Os {ins[0]} -o{outs[0]}"],
    label="FREEPASCAL",
)


@Rule
def mads(self, name, src: Target, deps: Targets = [], defines={}):
    ds = [f"-d:{k}={v}" for k, v in defines.items()]

    simplerule(
        replaces=self,
        ins=[src],
        outs=[f"={name}.bin"],
        deps=["third_party/mads"] + deps,
        commands=["chronic {deps[0]} {ins[0]} -c -o:{outs[0]} " + " ".join(ds)],
        label="MADS",
    )
