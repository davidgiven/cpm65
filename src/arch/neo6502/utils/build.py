from build.llvm import llvmprogram, llvmclibrary

llvmclibrary(
    name="neo6502",
    srcs=["./neo6502.c", "./neo6502.h"],
    hdrs={"neo6502.h": "./neo6502.h"},
    deps=["include"],
)

PROGRAMS = [
    "ncopy",
    "nattr",
    "ndir",
    "ntrunc",
]

for p in PROGRAMS:
    llvmprogram(
        name=p,
        srcs=["./" + p + ".c"],
        deps=[
            "include",
            ".+neo6502",
        ],
    )
