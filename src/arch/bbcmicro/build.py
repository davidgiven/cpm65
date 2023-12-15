from build.ab import normalrule
from tools.build import mkdfs, mkcpmfs

mkcpmfs(name="cpmfs", format="bbc192", items={"0:ccp.sys": "src+ccp"})

mkdfs(
    name="diskimage",
    out="bbcmicro.ssd",
    title="CP/M-65",
    opt=2,
    items={"bdos": "src+bdos", "cpmfs": ".+cpmfs"},
)
