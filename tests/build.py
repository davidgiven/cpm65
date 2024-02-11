from build.ab import export, normalrule
from build.llvm import llvmprogram

llvmprogram(
    name="parsefcb_test",
    srcs=["./parsefcb_test.S"],
    deps=["include", "src/bdos+bdoslib", "lib+cpm65"],
)

normalrule(
    name="run_parsefcb_test",
    ins=["tools/cpmemu", ".+parsefcb_test", "./parsefcb_test.good"],
    outs=["parsefcb_test.out"],
    commands=[
        "{ins[0]} {ins[1]} > {outs[0]}",
        "diff -u {outs[0]} {ins[2]}"
    ],
    label="TEST"
)

export(
    name="tests",
    deps=[".+run_parsefcb_test"]
)

