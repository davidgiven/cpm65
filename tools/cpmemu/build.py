from build.c import cprogram
from build.pkg import package

package(name="libreadline", package="readline")

cprogram(
    name="cpmemu",
    srcs=["./biosbdos.c", "./emulator.c", "./fileio.c", "./main.c"],
    deps=["third_party/lib6502", ".+libreadline"],
)
