from build.llvm import llvmclibrary, llvmprogram

llvmclibrary(
    name="bdoslib",
    srcs=[
        "./core.S",
        "./parsefcb.S",
        "./toupper.S",
        "./conio.S",
        "./dispatch.S",
        "./exit.S",
        "./utils.S",
    ],
    hdrs={"bdos.inc": "./bdos.inc"},
    deps=["include"],
)

llvmprogram(
    name="bdos",
    srcs=["./filesystem.S", "./main.S"],
    deps=["include", ".+bdoslib"],
)
