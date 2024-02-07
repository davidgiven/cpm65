from build.llvm import llvmclibrary, llvmprogram

llvmclibrary(
    name="bdoslib",
    srcs=[
        "./main.S",
        "./parsefcb.S",
        "./toupper.S",
        "./conio.S",
        "./dispatch.S",
        "./exit.S",
        "./utils.S",
        "./bios.S",
        "./filesystem.S",
    ],
    hdrs={"bdos.inc": "./bdos.inc"},
    deps=["include"],
)

llvmprogram(
    name="bdos",
    deps=["include", ".+bdoslib"],
    ldflags=["-Wl,--defsym=main=bdos_main"],
)
