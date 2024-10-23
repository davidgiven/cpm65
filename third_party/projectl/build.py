from build.ab import Rule, simplerule, Targets, Target
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
        label="PROJECTL_AS65C",
    )

@Rule
def l_link(self, name, srcs: Targets, relinfo, deps: Targets=[]):
    relinfostr=",".join(f"{segment}={hex(address)[2:]}" for segment, address in relinfo.items())
    simplerule(
        replaces=self,
        ins=srcs,
        deps=deps + glob("third_party/projectl/link/*.py"),
        outs=[f"={self.localname}.hex"],
        commands=[
            f"chronic python3 third_party/projectl/link/link.py -r {relinfostr} -o {{outs[0]}} -ls {{outs[0]}}.map {{ins}}"
        ],
        label="PROJECTL_LINK")

@Rule
def l_hex2bin(self, name, src: Target, romformat="4"):
    simplerule(
        replaces=self,
        ins=[src],
        deps=glob("third_party/projectl/hex2bin/*.py"),
        outs=[f"{self.localname}.bin"],
        commands=[
            f"chronic python3 third_party/projectl/hex2bin/hex2bin.py -r {romformat} -o {{outs[0]}} -f {{ins}}"
        ],
        label="PROJECTL_HEX2BIN")