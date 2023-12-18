from third_party.mads.build import mads
from tools.build import multilink, xextobin

VARIANTS = {
    "core": {"ZPBASE": 0, "TEXTBASE": 0x0200},
    "zp": {"ZPBASE": 1, "TEXTBASE": 0x0200},
    "tpa": {"ZPBASE": 0, "TEXTBASE": 0x0300},
}

for name, defines in VARIANTS.items():
    xex = mads(
        name=name + "_xex",
        src="./source/atbasic.s",
        deps=[
            "./kernel/mathpack.s",
            "./source/variables.s",
            "./source/list.s",
            "./source/error.s",
            "./source/printerror.s",
            "./source/statements.s",
            "./source/exec.s",
            "./source/math.s",
            "./source/io.s",
            "./source/parser.s",
            "./source/cioemu.s",
            "./source/util.s",
            "./source/parserbytecode.s",
            "./source/functions.s",
            "./source/evaluator.s",
            "./source/memory.s",
            "./source/data.s",
        ],
        defines=defines,
    )

    xextobin(name=name, src=xex, address=defines["TEXTBASE"])


multilink(name="altirrabasic", core=".+core", zp=".+zp", tpa=".+tpa")
