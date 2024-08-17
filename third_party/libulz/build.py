from build.c import clibrary

clibrary(
    name="libulz",
    hdrs={
        "tglist.h": "./include/tglist.h",
        "hbmap.h": "./include/hbmap.h",
        "bmap.h": "./include/bmap.h",
    })
