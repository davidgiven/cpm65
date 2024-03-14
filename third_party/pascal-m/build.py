from build.ab import normalrule, emit, Rule, Targets, Target
from build.llvm import llvmprogram

emit("FPC ?= fpc")

normalrule(
    name="pasc-cross",
    ins=["./cpascalm2k1.pas"],
    outs=["pasc"],
    deps=["./cpm.pas"],
    commands=["chronic $(FPC) -g -Mdelphi -Facpm -Os {ins[0]} -o{outs[0]}"],
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

llvmprogram(
    name="pint",
    srcs=["./pascalmint2k1.S"],
    deps=["lib+cpm65", "lib+bdos", "include"],
)

llvmprogram(
    name="loader",
    srcs=["./loader.c"],
    deps=["lib+cpm65"],
)


@Rule
def pascalm_obp(self, name, src: Target):
    normalrule(
        replaces=self,
        ins=[src],
        deps=["third_party/pascal-m+pasc-cross"],
        outs=["out.obp"],
        commands=["chronic {deps[0]} {ins[0]} {outs[0]}"],
        label="PASCALM-COMPILE",
    )


@Rule
def pascalm_load(self, name, src: Target):
    normalrule(
        replaces=self,
        ins=[src],
        outs=["out.obb"],
        deps=["tools/cpmemu", "third_party/pascal-m+loader"],
        commands=[
            'chronic sh -c "{deps[0]} {deps[1]} -pA=$(dir {ins[0]}) -pB=$(dir {outs[0]})'
            + ' a:$(notdir {ins[0]}) b:$(notdir {outs[0]}); test -f {outs[0]}"'
        ],
        label="PASCALM-LOAD",
    )


pascalm_obp(name="pasc-obp", src="./cpascalm2k1.pas")
pascalm_load(name="pasc-obb", src=".+pasc-obp")
