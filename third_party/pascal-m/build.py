from build.ab import normalrule, emit, Rule, Targets, Target

emit("FPC ?= fpc")

normalrule(
    name="pasc",
    ins=["./cpascalm2k1.pas"],
    outs=["pasc"],
    commands=["chronic $(FPC) -g -Mdelphi -Os {ins[0]} -o{outs[0]}"],
    label="FREEPASCAL",
)

normalrule(
    name="pasdis",
    ins=["./cpascalmdis.pas"],
    outs=["pasdis"],
    deps=["./pascalmdisassembler.inc"],
    commands=["chronic $(FPC) -g -Mdelphi -Os {ins[0]} -o{outs[0]}"],
    label="FREEPASCAL",
)

@Rule
def pascalm_obp(self, name, src:Target):
    normalrule(
        replaces=self,
        ins=[src],
        deps=["third_party/pascal-m+pasc"],
        outs=[name+".obp"],
        commands=[
            "{deps[0]} < {ins[0]} > {outs[0]}"
        ],
        label="PASCALM"
    )

pascalm_obp(
    name="pasc-obp",
    src="./cpascalm2k1.pas")
