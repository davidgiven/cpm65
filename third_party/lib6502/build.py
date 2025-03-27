from build.c import clibrary

clibrary(
    name="lib6502",
    srcs=["./lib6502.c", "./lib6502.h", "./6502data.h"],
    hdrs={
        "third_party/lib6502/6502data.h": "./6502data.h",
        "third_party/lib6502/lib6502.h": "./lib6502.h",
    },
)
