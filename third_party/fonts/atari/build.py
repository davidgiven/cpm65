from build.llvm import llvmclibrary

llvmclibrary(
    name="ivo3x6", hdrs={"third_party/fonts/atari/ivo3x6.inc": "./ivo3x6.inc"}
)
