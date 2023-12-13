from build.c import cprogram

cprogram(
    name="cpmemu",
    srcs=["./biosbdos.c", "./emulator.c", "./fileio.c", "./main.c"],
    deps=["third_party/lib6502", "+libreadline"],
)
