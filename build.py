from build.ab import export
from build.pkg import package

package(name="libreadline", package="readline")
package(name="libfmt", package="fmt")
package(name="libelf", package="libelf")

export(
    name="all",
    items={
        "bin/cpmemu": "tools/cpmemu",
        "bin/mads": "third_party/mads",
        "bin/atbasic.com": "third_party/altirrabasic",
        "bin/pasc": "third_party/pascal-m+pasc-cross",
        "bin/pasc.obp": "third_party/pascal-m+pasc-obp",
        "bin/pasc.obb": "third_party/pascal-m+pasc-obb",
        "bin/pasdis": "third_party/pascal-m+pasdis",
        "bin/pint.com": "third_party/pascal-m+pint",
        "bin/loader.com": "third_party/pascal-m+loader",
        "images/bbcmicro.ssd": "src/arch/bbcmicro+diskimage",
        "images/oric.dsk": "src/arch/oric+diskimage",
        "images/apple2e.po": "src/arch/apple2e+diskimage",
        "images/apple2e_b.po": "src/arch/apple2e+diskimage_b",
        "images/atari800.atr": "src/arch/atari800+atari800_diskimage",
        "images/atari800b.atr": "src/arch/atari800+atari800b_diskimage",
        "images/atari800c.atr": "src/arch/atari800+atari800c_diskimage",
        "images/atari800hd.atr": "src/arch/atari800+atari800hd_diskimage",
        "images/atari800xlhd.atr": "src/arch/atari800+atari800xlhd_diskimage",
        "images/c64.d64": "src/arch/commodore+c64_diskimage",
        "images/neo6502.zip": "src/arch/neo6502+diskimage",
        "images/osi400mf.os5": "src/arch/osi+osi400mf_diskimage",
        "images/osi500mf.os5": "src/arch/osi+osi500mf_diskimage",
        "images/osi600mf.os5": "src/arch/osi+osi600mf_diskimage",
        "images/osimf-b.os5": "src/arch/osi+osimf-b_diskimage",
        "images/osimf-c.os5": "src/arch/osi+osimf-c_diskimage",
        "images/osimf-d.os5": "src/arch/osi+osimf-d_diskimage",
        "images/osi400f.os8": "src/arch/osi+osi400f_diskimage",
        "images/osi500f.os8": "src/arch/osi+osi500f_diskimage",
        "images/osi600f.os8": "src/arch/osi+osi600f_diskimage",
        "images/osif-b.os8": "src/arch/osi+osif-b_diskimage",
        "images/osiserf.os8": "src/arch/osi+osiserf_diskimage",
        "images/osi600mf80.osi": "src/arch/osi+osi600mf80_diskimage",
        "images/osimf80-b.osi": "src/arch/osi+osimf80-b_diskimage",
        "images/osimf80-c.osi": "src/arch/osi+osimf80-c_diskimage",
        "images/osimf80-d.osi": "src/arch/osi+osimf80-d_diskimage",
        "images/pet4032.d64": "src/arch/commodore+pet4032_diskimage",
        "images/pet8032.d64": "src/arch/commodore+pet8032_diskimage",
        "images/pet8096.d64": "src/arch/commodore+pet8096_diskimage",
        "images/snes.smc": "src/arch/snes+snes_cartridge",
        "images/vic20_jiffy_1541.d64": "src/arch/commodore+vic20_jiffy_1541_diskimage",
        "images/vic20_yload_1541.d64": "src/arch/commodore+vic20_yload_1541_diskimage",
        "images/vic20_iec_1541.d64": "src/arch/commodore+vic20_iec_1541_diskimage",
        "images/vic20_jiffy_fd2000.d2m": "src/arch/commodore+vic20_jiffy_fd2000_diskimage",
        "images/vic20_iec_fd2000.d2m": "src/arch/commodore+vic20_iec_fd2000_diskimage",
        "images/x16.zip": "src/arch/x16+diskimage",
        "images/sorbus.zip": "src/arch/sorbus+diskimage",
        "images/nano6502.img": "src/arch/nano6502+diskimage",
        "images/nano6502_sysonly.img": "src/arch/nano6502+sysimage",
        "images/kim-1-k1013.zip": "src/arch/kim-1+distro-k1013",
        "images/kim-1-sdcard.zip": "src/arch/kim-1+distro-sdcard",
        "images/kim-1-iec.zip": "src/arch/kim-1+distro-iec",
        "images/kim-1-sdshield.zip": "src/arch/kim-1+distro-sdshield",
    },
    deps=["tests"],
)

export(
    name="mametest",
    deps=[
        "src/arch/bbcmicro+mametest",
        
        # Isn't accurate enough to support the fastloader.
        #"src/arch/commodore+c64_mametest",
        
        # As above, and also doesn't support enough memory expansions.
        #"src/arch/commodore+vic20_mametest",

        # MAME's ROM configuration is for the graphics keyboard, but MAME's
        # hardware emulates the business keyboard, so we can't interact with the
        # system.
        # "src/arch/commodore+pet4032_mametest",

        # MAME's ROM configuration is for the business keyboard, but MAME's
        # hardware emulates the graphics keyboard...
        # "src/arch/commodore+pet8032_mametest",

        # Works locally, but not on github CI.
        # "src/arch/apple2e+mametest",

        # Fails everywhere.
        # "src/arch/atari800+mametest",

        "src/arch/oric+mametest",
    ],
)
