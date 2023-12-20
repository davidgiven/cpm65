from build.ab import Rule, Target, Targets, normalrule
from build.llvm import llvmprogram


@Rule
def asm(self, name, src: Target = None, deps: Targets = []):
    normalrule(
        replaces=self,
        ins=[src],
        outs=["out.com"],
        deps=["tools/cpmemu", "apps+asm"] + deps,
        commands=[
            "chronic {deps[0]} {deps[1]} -pA=$(dir {ins[0]}) -pB=$(dir {outs[0]})"
            + " a:$(notdir {ins[0]}) b:$(notdir {outs[0]})",
            "test -f {outs[0]}",
        ],
        label="ASM",
    )


# CP/M-65 assembler programs.

for prog in [
    "bedit",
    "capsdrv",
    "cls",
    "cpuinfo",
    "devices",
    "dinfo",
    "dump",
    "ls",
    "scrntest",
    "xrecv",
]:
    asm(name=prog, src=("./%s.asm" % prog), deps=["./cpm65.inc"])

# Simple C programs.

for prog in ["asm", "copy", "stat", "submit", "objdump", "qe", "life"]:
    llvmprogram(name=prog, srcs=["./%s.c" % prog], deps=["lib+cpm65"])
