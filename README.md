CP/M-65
=======

What?
-----

This is a native port of Digital Research's seminal 1977 operating system CP/M
to the 6502. So far it runs on:

  - BBC Micro (and Master, and Tube, and Electron)
  - Commodore 64
  - Commander X16
  - Apple IIe (partially)

Unlike the original, it supports relocatable binaries, so allowing unmodified
binaries to run on any system: this is necessary as 6502 systems tend to be
much less standardised than 8080 and Z80 systems. On the BBC Micro in mode 7
you get a 21kB TPA, on the Master you get about 25kB, and on the C64 and Apple
IIe you get 46kB. A BBC Tube system will give you just under 57kB, which is
nice.

Currently you can cross-assemble programs from a PC, as well as a working C
toolchain with llvm-mos. For native development, there's a basic assembler but
currently no (functioning) editor.

No, it won't let you run 8080 programs on the 6502!

<div style="text-align: center">
<a href="doc/bbcmicro.png"><img src="doc/bbcmicro.png" style="width:40%" alt="CP/M-65 running on a BBC Micro"></a>
<a href="doc/c64.png"><img src="doc/c64.png" style="width:40%" alt="CP/M-65 running on a Commodore 64"></a>
<a href="doc/x16.png"><img src="doc/x16.png" style="width:40%" alt="CP/M-65 running on a Commander X16"></a>
</div>


Why?
----

Why not?


Where?
------

It's [open source on GitHub!](https://github.com/davidgiven/cpm65)


How?
----

You will need the [llvm-mos](https://llvm-mos.org) toolchain. CP/M-65 support
is available out of the box. Once installed, you should just be able to run the
Makefile and you'll get bootable disk images for the Commodore 64 (with 1541
drive) and BBC Micro (producing a 200kB SSSD DFS disk).

### BBC Micro notes

  - it'll autodetect the amount of available memory. If you're on a Master or
	Tube system, I'd suggest making sure you're in mode 0 or 3 before running.
	On a BBC Micro... well, it _will_ run in mode 0, but you'll only get a
	2.5kB TPA! I suggest mode 7.

  - the CP/M file system is stored in a big file (called cpmfs). This will
	expand up to the size defined in diskdefs: currently, 192kB (the largest
	that will fit on a SSSD disk). All disk access is done through MOS so you
	should be able to use a ramdisk, hard disk, Econet, ADFS, VDFS, etc. If so,
	you'll want to define your own disk format and adjust the drive definition
	in the BIOS to get more space.

### Commodore 64 notes

  - load and run the `CPM` program to start.

  - it's excruciatingly slow as it uses normal 1541 disk accesses at 300 bytes
	per second. Everything works, but you won't enjoy it. At some point I want
	to add a fastloader.

  - the disk image produced is a hybrid of a CP/M file system and a CBMDOS file
	system, which can be accessed as either. The disk structures used by the
	other file system are hidden. You get about 170kB on a normal disk.

  - disk accesses are done using direct block access, so it _won't_ work on
	anything other than a 1541. Sorry.

### Commander X16 notes

  - to use, place the contents of the `x16.zip` file on the X16's SD card. Load
	and run the `CPM` program to start.

  - the CP/M filesystem is stored in a big file called CPMFS. It needs support
	for the Position command in order to seek within the file. `x16emu`
	currently doesn't support this in its host filesystem, so you'll need to
	use an actual SD card image. (I have a [pull request
	outstanding](https://github.com/commanderx16/x16-emulator/pull/435) to add
	support. An SD2IEC should work too, as these support the same commands.
	However a real Commodore disk drive _will not work_.

### Apple IIe notes

  - this is still in development and doesn't support writing to disk yet.

  - to use, place the contents of the `appleiie.po` file onto a disk and boot
    it. The disk image has been munged according to ProDOS sector ordering.

  - It supports a single drive on slot 6 drive 1. You need a 80-column card
    (but not any aux memory).

  - this port runs completely bare-metal and does not use any ROM routines.

### Supported programs

You don't get a lot right now. As transients, you get `DUMP`, `STAT`, `COPY`,
`SUBMIT` and `ASM`. I'd love more --- send me pull requests! The build system
supports cc65 assembler and llvm-mos C programs.

In the CCP, you get the usual `DIR`, `ERA`, `TYPE` and `USER`. There is no
`SAVE` as on the relocatable CP/M-65 system assembling images in memory is of
questionable utility, but there's a new `FREE` command which shows memory
usage.

Pokey the Penguin loves to read your [pull
requests](https://github.com/davidgiven/cpm65/compare)!

### The assembler

The CP/M-65 assembler is extremely simple and very much customised to work for
the CP/M-65 environment. It operates entirely in memory (so it should be fast)
but it's written in C (so it's going to be big and slow). It's very very new
and is likely to have lots of bugs. There is, at least, a port of the DUMP
program to it which assembles, works, and is ready to play with.

Go read [cpmfs/asm.txt](cpmfs/asm.txt) for the documentation. 

### Utilities

`bin/cpmemu` contains a basic CP/M-65 user mode emulator and debugger. It'll run
programs on the host environment with an emulated disk, which is very useful for
testing and development. To use:

`./bin/cpmemu .obj/dump.com diskdefs`

Add `-d` at the front of the command line to drop into the debugger --- use `?`
for basic help. It can only access 8.3-format all-lowercase filenames in the
current directory, but you can also map drives. Use `-h` for help.

Who?
----

You may contact me at dg@cowlark.com, or visit my website at
http://www.cowlark.com.  There may or may not be anything interesting there.
The CP/M-65 project was designed and written by me, David Given. 


License
-------

Everything here so far _except_ the contents of the `third_party` directory is
© 2022-2023 David Given, and is licensed under the two-clause BSD open source
license. Please see [LICENSE](LICENSE) for the full text. The tl;dr is: you can
do what you like with it provided you don't claim you wrote it.

The exceptions are the contents of the `third_party` directory, which were
written by other people and are not covered by this license. This directory as
a whole contains GPL software, which means that if you redistribute the entire
directory, you must conform to the terms of the GPL.

`third_party/lib6502` contains a hacked copy of the lib6502 library, which is ©
2005 Ian Plumarta and is available under the terms of the MIT license. See
`third_party/lib6502/COPYING.lib6502` for the full text.


