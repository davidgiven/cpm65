from build.ab import Rule, simplerule, Targets
from build.utils import filenamesmatchingof
from glob import glob


@Rule
def l_as65c(self, name, srcs: Targets, deps: Targets = []):
    realsrcs = filenamesmatchingof(srcs, "*.asm")
    assert len(realsrcs) == 1, "exactly one .asm file must be supplied"
    simplerule(
        replaces=self,
        ins=srcs,
        outs=[f"={self.localname}.rel"],
        deps=deps + glob("third_party/projectl/as65c/*.py"),
        commands=[
            "chronic python3 third_party/projectl/as65c/as65c.py -f "
            + realsrcs[0]
            + " -o {outs[0]}"
        ],
        label="AS65C",
    )
