from build.c import cprogram

cprogram(
    name="cpmemu",
    srcs=[
        "./biosbdos.c",
        "./emulator.c",
        "./fileio.c",
        "./screen.c",
        "./main.c",
        "./globals.h",
    ],
    deps=["third_party/lib6502", "+libreadline"],
)
