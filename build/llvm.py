from build.ab import Rule, Targets, Target
from build.toolchain import Toolchain
from build.c import cprogram, clibrary, cfile


class LlvmToolchain(Toolchain):
    PREFIX = "LLVM"
    CC = ["$(CC6502) -c -o $[outs[0]] $[ins[0]] $(CFLAGS6502) $[cflags]"]
    CLINK = ["$(CC6502) -o $[outs[0]] $[ins] $[ldflags] $(LDFLAGS6502)"]
    AR = ["$(AR6502) cqs $[outs[0]] $[ins]"]


class LlvmRawToolchain(LlvmToolchain):
    PREFIX = "LLVMRAW"
    CLINK = [
        "$(LD6502) -Map $[outs[0]].map -T $[linkscript] -o $[outs[0]] $[ins] $[ldflags]"
    ]


def llvmprogram(**kwargs):
    kwargs["toolchain"] = LlvmToolchain
    return cprogram(**kwargs)


def llvmclibrary(**kwargs):
    kwargs["toolchain"] = LlvmToolchain
    return clibrary(**kwargs)


def llvmcfile(**kwargs):
    kwargs["toolchain"] = LlvmToolchain
    return cfile(**kwargs)


@Rule
def llvmrawprogram(
    self, name, linkscript: Target, deps: Targets = [], **kwargs
):
    cprogram(
        replaces=self,
        deps=deps + [linkscript],
        toolchain=LlvmRawToolchain,
        args={"linkscript": linkscript},
        **kwargs
    )
