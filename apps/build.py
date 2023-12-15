from build.llvm import llvmprogram

for prog in ["asm", "copy", "stat", "submit", "objdump", "qe", "life"]:
    llvmprogram(name=prog, srcs=["./%s.c" % prog], deps=["lib+cpm65"])
