MINIMAL_APPS = {
    "0:asm.com": "apps+asm",
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
    "0:bedit.asm": "apps/bedit.asm",
    "0:dump.asm": "apps/dump.asm",
    "0:ls.asm": "apps/ls.asm",
    "0:cpm65.inc": "apps/cpm65.inc",
    "0:drivers.inc": "apps/drivers.inc",
}

BIG_APPS = {
    "0:atbasic.com": "third_party/altirrabasic",
    "0:objdump.com": "apps+objdump",
    "0:scrntest.com": "apps+scrntest",
    "0:kbdtest.com": "apps+kbdtest",
    "0:ansiterm.com": "apps+ansiterm",
}

BIG_APPS_SRCS = {}

SCREEN_APPS = {
    "0:cls.com": "apps+cls",
    "0:life.com": "apps+life",
    "0:qe.com": "apps+qe",
    "0:vt52drv.com": "apps+vt52drv",
    "0:vt52test.com": "apps+vt52test",
}

SCREEN_APPS_SRCS = {"0:cls.asm": "apps/cls.asm"}
