CXX = g++
CC = gcc

CFLAGS = -Os -g -I.
CFLAGS65 = -Os -g -I. \
	-Wno-main-return-type \
	-Wno-incompatible-library-redeclaration

OBJDIR = .obj

TARGETS = \
	apple2e.po \
	atari800.atr \
	atari800hd.atr \
	atari800xlhd.atr \
	bbcmicro.ssd \
	c64.d64 \
	oric.dsk \
	pet4032.d64 \
	pet8032.d64 \
	pet8096.d64 \
	vic20.d64 \
	x16.zip \

APPS = \
	$(OBJDIR)/apps/bedit.com \
	$(OBJDIR)/apps/capsdrv.com \
	$(OBJDIR)/apps/cls.com \
	$(OBJDIR)/apps/devices.com \
	$(OBJDIR)/apps/dinfo.com \
	$(OBJDIR)/apps/dump.com \
	$(OBJDIR)/apps/ls.com \
	$(OBJDIR)/asm.com \
	$(OBJDIR)/copy.com \
	$(OBJDIR)/objdump.com \
	$(OBJDIR)/stat.com \
	$(OBJDIR)/submit.com \
	apps/bedit.asm \
	apps/dinfo.asm \
	apps/dump.asm \
	apps/ls.asm \
	apps/cpm65.inc \
	apps/drivers.inc \
	cpmfs/asm.txt \
	cpmfs/bedit.txt \
	cpmfs/demo.sub \
	cpmfs/hello.asm \

SCREEN_APPS = \
	apps/cls.asm \
	$(OBJDIR)/qe.com \

MINIMAL_APPS = \
	$(OBJDIR)/apps/bedit.com \
	$(OBJDIR)/apps/capsdrv.com \
	$(OBJDIR)/apps/cls.com \
	$(OBJDIR)/apps/devices.com \
	$(OBJDIR)/apps/dinfo.com \
	$(OBJDIR)/apps/dump.com \
	$(OBJDIR)/apps/ls.com \
	$(OBJDIR)/asm.com \
	$(OBJDIR)/copy.com \
	$(OBJDIR)/stat.com \
	$(OBJDIR)/submit.com \
	apps/dump.asm \
	apps/ls.asm \

LIBCPM_OBJS = \
	$(OBJDIR)/lib/printi.o \
	$(OBJDIR)/lib/bdos.o \
	$(OBJDIR)/lib/xfcb.o \
	$(OBJDIR)/lib/screen.o \

LIBBIOS_OBJS = \
	$(OBJDIR)/src/bios/biosentry.o \
	$(OBJDIR)/src/bios/relocate.o \
	$(OBJDIR)/src/bios/loader.o \

LIBCOMMODORE_OBJS = \
	$(OBJDIR)/src/bios/commodore/ieee488.o \
	$(OBJDIR)/src/bios/commodore/petscii.o \

CPMEMU_OBJS = \
	$(OBJDIR)/tools/cpmemu/main.o \
	$(OBJDIR)/tools/cpmemu/emulator.o \
	$(OBJDIR)/tools/cpmemu/fileio.o \
	$(OBJDIR)/tools/cpmemu/biosbdos.o \
	$(OBJDIR)/third_party/lib6502/lib6502.o \

all: $(TARGETS)

$(OBJDIR)/multilink: $(OBJDIR)/tools/multilink.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $< -lfmt

$(OBJDIR)/mkdfs: $(OBJDIR)/tools/mkdfs.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $<

$(OBJDIR)/mkoricdsk: $(OBJDIR)/tools/mkoricdsk.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $< -lfmt

bin/cpmemu: $(CPMEMU_OBJS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $(CPMEMU_OBJS) -lreadline

bin/shuffle: $(OBJDIR)/tools/shuffle.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $<

bin/fontconvert: $(OBJDIR)/tools/fontconvert.o $(OBJDIR)/tools/libbdf.o
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $^

$(OBJDIR)/mkcombifs: $(OBJDIR)/tools/mkcombifs.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $^ -lfmt

$(OBJDIR)/third_party/%.o: third_party/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/third_party/%.o: third_party/%.cc
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/tools/%.o: tools/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/tools/%.o: tools/%.cc
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/%.o: %.S include/zif.inc include/mos.inc include/cpm65.inc include/driver.inc
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -c -o $@ $< -I include

$(OBJDIR)/libcommodore.a: $(LIBCOMMODORE_OBJS)
	@mkdir -p $(dir $@)
	llvm-ar rs $@ $^

$(OBJDIR)/libbios.a: $(LIBBIOS_OBJS)
	@mkdir -p $(dir $@)
	llvm-ar rs $@ $^

$(OBJDIR)/libcpm.a: $(LIBCPM_OBJS)
	@mkdir -p $(dir $@)
	llvm-ar rs $@ $^

$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -c -I. -o $@ $^

$(OBJDIR)/%.com: $(OBJDIR)/apps/%.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/%.com: %.asm $(OBJDIR)/asm.com bin/cpmemu $(wildcard apps/*.inc)
	@mkdir -p $(dir $@)
	bin/cpmemu $(OBJDIR)/asm.com -pA=$(dir $<) -pB=$(dir $@) \
		a:$(notdir $<) b:$(notdir $@)
	test -f $@

$(OBJDIR)/bdos.sys: $(OBJDIR)/src/bdos.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/ccp.sys: $(OBJDIR)/src/ccp.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/apple2e.bios: $(OBJDIR)/src/bios/apple2e.o $(OBJDIR)/libbios.a scripts/apple2e.ld scripts/apple2e-prelink.ld Makefile
	@mkdir -p $(dir $@)
	ld.lld -T scripts/apple2e-prelink.ld -o $(OBJDIR)/apple2e.o $< $(OBJDIR)/libbios.a --defsym=BIOS_SIZE=0x8000
	ld.lld -Map $(patsubst %.bios,%.map,$@) -T scripts/apple2e.ld -o $@ $< $(OBJDIR)/libbios.a --defsym=BIOS_SIZE=$$(llvm-objdump --section-headers $(OBJDIR)/apple2e.o | gawk --non-decimal-data '/ [0-9]+/ { size[$$2] = ("0x"$$3)+0 } END { print(size[".text"] + size[".data"] + size[".bss"]) }')
	
$(OBJDIR)/oric.exe: $(OBJDIR)/src/bios/oric.o $(OBJDIR)/libbios.a scripts/oric.ld scripts/oric-prelink.ld scripts/oric-common.ld Makefile
	@mkdir -p $(dir $@)
	ld.lld -Map -T scripts/oric-prelink.ld -o $(OBJDIR)/oric-prelink.o $< $(OBJDIR)/libbios.a --defsym=BIOS_SIZE=0x4000
	ld.lld -Map $(patsubst %.exe,%.map,$@) -T scripts/oric.ld -o $@ $< $(OBJDIR)/libbios.a --defsym=BIOS_SIZE=$$(llvm-objdump --section-headers $(OBJDIR)/oric-prelink.o | gawk --non-decimal-data '/ [0-9]+/ { size[$$2] = ("0x"$$3)+0 } END { print(size[".text"] + size[".data"] + size[".bss"]) }')
	
$(OBJDIR)/%.exe: $(OBJDIR)/src/bios/%.o $(OBJDIR)/libbios.a scripts/%.ld
	@mkdir -p $(dir $@)
	ld.lld -Map $(patsubst %.exe,%.map,$@) -T scripts/$*.ld -o $@ $< $(filter %.a,$^) $(LINKFLAGS)

$(OBJDIR)/4x8font.inc: bin/fontconvert third_party/tomsfonts/atari-small.bdf
	@mkdir -p $(dir $@)
	bin/fontconvert third_party/tomsfonts/atari-small.bdf > $@
	
$(OBJDIR)/bbcmicrofs.img: $(APPS) $(SCREEN_APPS) $(OBJDIR)/ccp.sys
	mkfs.cpm -f bbc192 $@
	cpmcp -f bbc192 $@ $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmchattr -f bbc192 $@ sr 0:ccp.sys

bbcmicro.ssd: $(OBJDIR)/bbcmicro.exe $(OBJDIR)/bdos.sys Makefile $(OBJDIR)/bbcmicrofs.img $(OBJDIR)/mkdfs
	$(OBJDIR)/mkdfs -O $@ \
		-N CP/M-65 \
		-f $(OBJDIR)/bbcmicro.exe -n \!boot -l 0x400 -e 0x400 -B 2 \
		-f $(OBJDIR)/bdos.sys -n bdos \
		-f $(OBJDIR)/bbcmicrofs.img -n cpmfs

$(OBJDIR)/c64.exe: $(OBJDIR)/libcommodore.a
c64.d64: $(OBJDIR)/c64.exe $(OBJDIR)/bdos.sys Makefile $(APPS) $(OBJDIR)/ccp.sys \
		$(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/c64.exe \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f c1541 $@ sr 0:bdos.sys 0:ccp.sys 0:cbmfs.sys

$(OBJDIR)/generic-1m-cpmfs.img: $(OBJDIR)/bdos.sys $(APPS) $(OBJDIR)/ccp.sys
	@rm -f $@
	mkfs.cpm -f generic-1m $@
	cpmcp -f generic-1m $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f generic-1m $@ sr 0:ccp.sys

$(OBJDIR)/x16.exe: $(OBJDIR)/libcommodore.a
x16.zip: $(OBJDIR)/x16.exe $(OBJDIR)/bdos.sys $(OBJDIR)/generic-1m-cpmfs.img
	@rm -f $@
	zip -9 $@ -j $^
	printf "@ x16.exe\n@=CPM\n" | zipnote -w $@
	printf "@ bdos.sys\n@=BDOS\n" | zipnote -w $@
	printf "@ generic-1m-cpmfs.img\n@=CPMFS\n" | zipnote -w $@

$(OBJDIR)/apple2e.bios.swapped: $(OBJDIR)/apple2e.bios bin/shuffle
	bin/shuffle -i $< -o $@ -b 256 -t 16 -r -m 02468ace13579bdf

$(OBJDIR)/apple2e.boottracks: $(OBJDIR)/apple2e.bios.swapped
	cp $(OBJDIR)/apple2e.bios.swapped $@
	truncate -s 4096 $@

apple2e.po: $(OBJDIR)/apple2e.boottracks $(OBJDIR)/bdos.sys $(APPS) $(OBJDIR)/ccp.sys Makefile diskdefs bin/shuffle
	@rm -f $@
	mkfs.cpm -f appleiie -b $(OBJDIR)/apple2e.boottracks $@
	cpmcp -f appleiie $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f appleiie $@ sr 0:ccp.sys 0:bdos.sys
	truncate -s 143360 $@

$(OBJDIR)/pet4032.exe: LINKFLAGS += --no-check-sections
$(OBJDIR)/pet4032.exe: $(OBJDIR)/libcommodore.a
$(OBJDIR)/src/bios/pet4032.o: CFLAGS65 += -DPET4032
pet4032.d64: $(OBJDIR)/pet4032.exe $(OBJDIR)/bdos.sys Makefile $(APPS) $(SCREEN_APPS) $(OBJDIR)/ccp.sys \
		$(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -i 15 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/pet4032.exe \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmchattr -f c1541 $@ sr 0:ccp.sys 0:cbmfs.sys 0:bdos.sys

$(OBJDIR)/pet8096.exe: LINKFLAGS += --no-check-sections
$(OBJDIR)/pet8096.exe: $(OBJDIR)/libcommodore.a
$(OBJDIR)/src/bios/pet8096.o: CFLAGS65 += -DPET8096
pet8096.d64: $(OBJDIR)/pet8096.exe $(OBJDIR)/bdos.sys Makefile $(APPS) $(SCREEN_APPS) $(OBJDIR)/ccp.sys \
		$(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -i 15 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/pet8096.exe \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmchattr -f c1541 $@ sr 0:ccp.sys 0:cbmfs.sys 0:bdos.sys

$(OBJDIR)/pet8032.exe: LINKFLAGS += --no-check-sections
$(OBJDIR)/pet8032.exe: $(OBJDIR)/libcommodore.a
$(OBJDIR)/src/bios/pet8032.o: CFLAGS65 += -DPET8032
pet8032.d64: $(OBJDIR)/pet8032.exe $(OBJDIR)/bdos.sys Makefile $(APPS) $(SCREEN_APPS) $(OBJDIR)/ccp.sys \
		$(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -i 15 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/pet8032.exe \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmchattr -f c1541 $@ sr 0:ccp.sys 0:cbmfs.sys 0:bdos.sys

$(OBJDIR)/vic20.exe: LINKFLAGS += --no-check-sections
$(OBJDIR)/vic20.exe: $(OBJDIR)/libcommodore.a
$(OBJDIR)/src/bios/vic20.o: $(OBJDIR)/4x8font.inc
vic20.d64: $(OBJDIR)/vic20.exe $(OBJDIR)/bdos.sys Makefile $(APPS) \
		$(OBJDIR)/ccp.sys $(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -i 15 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/vic20.exe \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f c1541 $@ sr 0:cbmfs.sys 0:ccp.sys 0:bdos.sys

# Atari targets call /usr/bin/printf directly because 'make' calls /bin/sh
# which might be the Defective Annoying SHell which has a broken printf
# implementation.

$(OBJDIR)/src/bios/atari800.o: CFLAGS65 += -DATARI_SD
$(OBJDIR)/atari800.exe:
atari800.atr: $(OBJDIR)/atari800.exe $(OBJDIR)/bdos.sys Makefile \
			$(MINIMAL_APPS) $(OBJDIR)/ccp.sys $(OBJDIR)/a8setfnt.com \
			$(SCREEN_APPS)
	dd if=/dev/zero of=$@ bs=128 count=720
	mkfs.cpm -f atari90 $@
	cp $(OBJDIR)/a8setfnt.com $(OBJDIR)/setfnt.com
	cpmcp -f atari90 $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(MINIMAL_APPS) $(SCREEN_APPS) 0:
	cpmcp -f atari90 $@ $(OBJDIR)/apps/ls.com $(OBJDIR)/setfnt.com third_party/fonts/atari/olivetti.fnt 1:
	cpmchattr -f atari90 $@ sr 0:ccp.sys o:bdos.sys
	dd if=$(OBJDIR)/atari800.exe of=$@ bs=128 conv=notrunc
	mv $@ $@.raw
	/usr/bin/printf '\x96\x02\x80\x16\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > $@
	cat $@.raw >> $@
	rm $@.raw

$(OBJDIR)/src/bios/atari800hd.o: CFLAGS65 += -DATARI_HD
$(OBJDIR)/atari800hd.exe:
atari800hd.atr: $(OBJDIR)/atari800hd.exe $(OBJDIR)/bdos.sys Makefile \
			$(APPS) $(OBJDIR)/ccp.sys $(OBJDIR)/a8setfnt.com \
			$(SCREEN_APPS)
	dd if=/dev/zero of=$@ bs=128 count=8190
	mkfs.cpm -f atarihd $@
	cp $(OBJDIR)/a8setfnt.com $(OBJDIR)/setfnt.com
	cpmcp -f atarihd $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmcp -f atarihd $@ $(OBJDIR)/apps/ls.com $(OBJDIR)/setfnt.com third_party/fonts/atari/*.fnt 1:
	cpmchattr -f atarihd $@ sr 0:ccp.sys 0:bdos.sys
	dd if=$(OBJDIR)/atari800hd.exe of=$@ bs=128 conv=notrunc
	mv $@ $@.raw
	/usr/bin/printf '\x96\x02\xf0\xff\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > $@
	cat $@.raw >> $@
	rm $@.raw

$(OBJDIR)/src/bios/atari800xlhd.o: CFLAGS65 += -DATARI_HD -DATARI_XL
$(OBJDIR)/atari800xlhd.exe:
atari800xlhd.atr: $(OBJDIR)/atari800xlhd.exe $(OBJDIR)/bdos.sys Makefile \
			$(APPS) $(OBJDIR)/ccp.sys $(OBJDIR)/a8setfnt.com \
			$(SCREEN_APPS)
	dd if=/dev/zero of=$@ bs=128 count=8190
	mkfs.cpm -f atarihd $@
	cp $(OBJDIR)/a8setfnt.com $(OBJDIR)/setfnt.com
	cpmcp -f atarihd $@ $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmcp -f atarihd $@ $(OBJDIR)/apps/ls.com $(OBJDIR)/setfnt.com third_party/fonts/atari/*.fnt 1:
	cpmchattr -f atarihd $@ sr 0:ccp.sys 0:bdos.sys
	dd if=$(OBJDIR)/atari800xlhd.exe of=$@ bs=128 conv=notrunc
	mv $@ $@.raw
	/usr/bin/printf '\x96\x02\xf0\xff\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > $@
	cat $@.raw >> $@
	rm $@.raw

$(OBJDIR)/oric.exe:
oric.dsk: $(OBJDIR)/oric.exe $(OBJDIR)/bdos.sys Makefile \
			$(APPS) $(SCREEN_APPS) $(OBJDIR)/ccp.sys $(OBJDIR)/mkoricdsk
	mkfs.cpm -f oric -b $(OBJDIR)/oric.exe $(OBJDIR)/oric.img
	cpmcp -f oric $(OBJDIR)/oric.img $(OBJDIR)/bdos.sys $(OBJDIR)/ccp.sys $(APPS) $(SCREEN_APPS) 0:
	cpmchattr -f oric $(OBJDIR)/oric.img sr 0:ccp.sys 0:bdos.sys
	$(OBJDIR)/mkoricdsk -i $(OBJDIR)/oric.img -o $@

clean:
	rm -rf $(OBJDIR) bin $(TARGETS)

.DELETE_ON_ERROR:
.SECONDARY:

