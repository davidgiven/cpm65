from build.ab import export
from build.pkg import package

package(name="libreadline", package="readline")
package(name="libfmt", package="fmt")

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
        "bbcmicro.ssd": "src/arch/bbcmicro+diskimage",
        "bbcmicro2.ssd": "src/arch/bbcmicro+diskimage2",
        "oric.dsk": "src/arch/oric+diskimage",
        "apple2e.po": "src/arch/apple2e+diskimage",
        "apple2e_b.po": "src/arch/apple2e+diskimage_b",
        "atari800.atr": "src/arch/atari800+atari800_diskimage",
        "atari800b.atr": "src/arch/atari800+atari800b_diskimage",
        "atari800c.atr": "src/arch/atari800+atari800c_diskimage",
        "atari800hd.atr": "src/arch/atari800+atari800hd_diskimage",
        "atari800xlhd.atr": "src/arch/atari800+atari800xlhd_diskimage",
        "c64.d64": "src/arch/commodore+c64_diskimage",
        "neo6502.zip": "src/arch/neo6502+diskimage",
        "osi400mf.os5": "src/arch/osi+osi400mf_diskimage",
        "osi500mf.os5": "src/arch/osi+osi500mf_diskimage",
        "osi600mf.os5": "src/arch/osi+osi600mf_diskimage",
        "osimf-b.os5": "src/arch/osi+osimf-b_diskimage",
        "osimf-c.os5": "src/arch/osi+osimf-c_diskimage",
        "osimf-d.os5": "src/arch/osi+osimf-d_diskimage",
        "osi400f.os8": "src/arch/osi+osi400f_diskimage",
        "osi500f.os8": "src/arch/osi+osi500f_diskimage",
        "osi600f.os8": "src/arch/osi+osi600f_diskimage",
        "osif-b.os8": "src/arch/osi+osif-b_diskimage",
        "osiserf.os8": "src/arch/osi+osiserf_diskimage",
        "pet4032.d64": "src/arch/commodore+pet4032_diskimage",
        "pet8032.d64": "src/arch/commodore+pet8032_diskimage",
        "pet8096.d64": "src/arch/commodore+pet8096_diskimage",
        "snes.smc": "src/arch/snes+snes_cartridge",
        "vic20.d64": "src/arch/commodore+vic20_diskimage",
        "x16.zip": "src/arch/x16+diskimage",
        "sorbus.zip": "src/arch/sorbus+diskimage",
        "nano6502.img": "src/arch/nano6502+diskimage",
        "nano6502_sysonly.img": "src/arch/nano6502+sysimage",
        "kim-1-k1013.zip": "src/arch/kim-1+distro-k1013",
        "kim-1-sdcard.zip": "src/arch/kim-1+distro-sdcard",
        "kim-1-iec.zip": "src/arch/kim-1+distro-iec",
    },
    deps=[
        "tests"
    ],
)

export(
    name="mametest",
    deps=[
        "src/arch/bbcmicro+mametest",
        "src/arch/commodore+c64_mametest",
        
        # MAME's ROM configuration is for the graphics keyboard, but MAME's
        # hardware emulates the business keyboard, so we can't interact with the
        # system.
        #"src/arch/commodore+pet4032_mametest",

        # MAME's ROM configuration is for the business keyboard, but MAME's
        # hardware emulates the graphics keyboard...
        #"src/arch/commodore+pet8032_mametest",

        # Works locally, but not on github CI.
        #"src/arch/apple2e+mametest",

        # Fails everywhere.
        #"src/arch/atari800+mametest",

        "src/arch/oric+mametest",
    ],
)
