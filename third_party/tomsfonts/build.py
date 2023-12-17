from build.llvm import llvmclibrary
from tools.build import fontconvert

llvmclibrary(
    name="ivo3x6", hdrs={"third_party/fonts/atari/ivo3x6.inc": "./ivo3x6.inc"}
)

fontconvert(name="4x8_h", src="./atari-small.bdf")

llvmclibrary(name="4x8", hdrs={"4x8font.inc": ".+4x8_h"})
