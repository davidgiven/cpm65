MINIMAL_APPS = {
    "0:asm.txt": "cpmfs+asm_txt_cpm",
    "0:hello.asm": "cpmfs+hello_asm_cpm",
    "0:demo.sub": "cpmfs+demo_sub_cpm",
    "0:asm.com": "apps+asm",
    "0:attr.com": "apps+attr",
    "0:bedit.com": "apps+bedit",
    "0:capsdrv.com": "apps+capsdrv",
    "0:copy.com": "apps+copy",
    "0:cpuinfo.com": "apps+cpuinfo",
    "0:devices.com": "apps+devices",
    "0:dinfo.com": "apps+dinfo",
    "0:dump.com": "apps+dump",
    "0:ls.com": "apps+ls",
    "0:stat.com": "apps+stat",
    "0:submit.com": "apps+submit",
    "0:xrecv.com": "apps+xrecv",
    "0:xsend.com": "apps+xsend",
}

# Programs which only work on a real CP/M filesystem (not emulation).
CPM_FILESYSTEM_APP_NAMES = {"0:dinfo.com", "0:stat.com"}

MINIMAL_APPS_SRCS = {
    "0:bedit.asm": "apps+bedit_asm_cpm",
    "0:bedit.txt": "cpmfs+bedit_txt_cpm",
    "0:dump.asm": "apps+dump_asm_cpm",
    "0:ls.asm": "apps+ls_asm_cpm",
    "0:cpm65.inc": "apps+cpm65_inc_cpm",
    "0:drivers.inc": "apps+drivers_inc_cpm",
}

BIG_APPS = {
    "0:atbasic.com": "third_party/altirrabasic",
    "0:atbasic.txt": "cpmfs+atbasic_txt_cpm",
    "0:objdump.com": "apps+objdump",
    "0:kbdtest.com": "apps+kbdtest",
    "0:ansiterm.com": "apps+ansiterm",
}

BIG_APPS_SRCS = {}

SCREEN_APPS = {
    "0:adm3adrv.com": "apps+adm3adrv",
    "0:adm3atst.com": "apps+adm3atst",
    "0:cls.com": "apps+cls",
    "0:life.com": "apps+life",
    "0:qe.com": "apps+qe",
    "0:scrntest.com": "apps+scrntest",
    "0:vt52drv.com": "apps+vt52drv",
    "0:vt52test.com": "apps+vt52test",
}

SCREEN_APPS_SRCS = {"0:cls.asm": "apps+cls_asm_cpm"}

PASCAL_APPS = {
    "0:pint.com": "third_party/pascal-m+pint",
    "0:pasc.obb": "third_party/pascal-m+pasc-obb",
    "0:pload.com": "third_party/pascal-m+loader",
    "0:hello.pas": "cpmfs+hello_pas_cpm",
}
