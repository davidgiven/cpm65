from build.ab import normalrule, emit, Rule, Targets, Target

emit("FPC ?= fpc")

normalrule(
    name="pasc",
    ins=["./cpascalm2k1.pas"],
    outs=["pasc"],
    commands=["chronic $(FPC) -Mdelphi -Os {ins[0]} -o{outs[0]}"],
    label="FREEPASCAL",
)

normalrule(
    name="pasdis",
    ins=["./cpascalmdis.pas"],
    outs=["pasdis"],
    deps=["./pascalmdisassembler.inc"],
    commands=["chronic $(FPC) -Mdelphi -Os {ins[0]} -o{outs[0]}"],
    label="FREEPASCAL",
)
