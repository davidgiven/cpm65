from build.ab import export
from build.pkg import package

package(name="libreadline", package="readline")
package(name="libfmt", package="fmt")

export(
    name="all",
    items={
        "bin/cpmemu": "tools/cpmemu",
        "bin/mads": "third_party/mads",
        "bin/atbasic.com": "third_party/altirrabasic",
        "bbcmicro.ssd": "src/arch/bbcmicro+diskimage",
        "oric.dsk": "src/arch/oric+diskimage",
        "apple2e.po": "src/arch/apple2e+diskimage",
    },
)
