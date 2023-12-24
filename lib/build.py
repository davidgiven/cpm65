from build.llvm import llvmclibrary

llvmclibrary(name="bdos", srcs=["./bdos.S"], deps=["include"])
llvmclibrary(name="xfcb", srcs=["./xfcb.S"], deps=["include"])

llvmclibrary(
    name="cpm65",
    srcs=["./printi.S", "./screen.S", "./serial.S"],
    hdrs={"lib/printi.h": "./printi.h", "lib/screen.h": "./screen.h", 
	  "lib/serial.h": "./serial.h"},
    deps=["include"],
)
