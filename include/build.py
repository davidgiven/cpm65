from build.llvm import llvmclibrary

llvmclibrary(
    name="include",
    hdrs={
        "cpm65.inc": "./cpm65.inc",
        "driver.inc": "./driver.inc",
        "jumptables.inc": "./jumptables.inc",
        "wait.inc": "./wait.inc",
        "zif.inc": "./zif.inc",
    },
)
