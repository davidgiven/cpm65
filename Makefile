CXX = g++
CC = gcc

CFLAGS = -Os -g -I.
CFLAGS65 = -Os -g -fnonreentrant -I.

OBJDIR = .obj

APPS = \
	$(OBJDIR)/submit.com \
	$(OBJDIR)/stat.com \
	$(OBJDIR)/copy.com \
	$(OBJDIR)/asm.com \
	$(OBJDIR)/apps/dump.com \
	$(OBJDIR)/third_party/dos65/edit205.com \
	third_party/dos65/edit205.asm \
	cpmfs/asm.txt \
	cpmfs/hello.asm \
	cpmfs/test.sub \
	apps/dump.asm \

LIBCPM_OBJS = \
	$(OBJDIR)/lib/printi.o \
	$(OBJDIR)/lib/bdos.o \
	$(OBJDIR)/lib/xfcb.o \

LIBBIOS_OBJS = \
	$(OBJDIR)/src/bios/biosentry.o \
	$(OBJDIR)/src/bios/commodore/ieee488.o \
	$(OBJDIR)/src/bios/commodore/petscii.o \
	$(OBJDIR)/src/bios/relocate.o \

CPMEMU_OBJS = \
	$(OBJDIR)/tools/cpmemu/main.o \
	$(OBJDIR)/tools/cpmemu/emulator.o \
	$(OBJDIR)/tools/cpmemu/fileio.o \
	$(OBJDIR)/tools/cpmemu/biosbdos.o \
	$(OBJDIR)/third_party/lib6502/lib6502.o \

all: apple2e.po c64.d64 bbcmicro.ssd x16.zip pet.d64 vic20.d64 bin/cpmemu

$(OBJDIR)/multilink: $(OBJDIR)/tools/multilink.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $< -lfmt

$(OBJDIR)/mkdfs: $(OBJDIR)/tools/mkdfs.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $<

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

$(OBJDIR)/%.o: %.S include/zif.inc include/mos.inc include/cpm65.inc
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -c -o $@ $< -I include

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

$(OBJDIR)/%.com: %.asm $(OBJDIR)/asm.com bin/cpmemu
	@mkdir -p $(dir $@)
	bin/cpmemu $(OBJDIR)/asm.com -pA=$(dir $<) -pB=$(dir $@) \
		a:$(notdir $<) b:$(notdir $@)
	test -f $@

$(OBJDIR)/bdos.img: $(OBJDIR)/src/bdos.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/ccp.sys: $(OBJDIR)/src/ccp.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/apple2e.bios: $(OBJDIR)/src/bios/apple2e.o $(OBJDIR)/libbios.a scripts/apple2e.ld scripts/apple2e-prelink.ld Makefile
	@mkdir -p $(dir $@)
	ld.lld -T scripts/apple2e-prelink.ld -o $(OBJDIR)/apple2e.o $< $(OBJDIR)/libbios.a --defsym=BIOS_SIZE=0x8000
	ld.lld -Map $(patsubst %.bios,%.map,$@) -T scripts/apple2e.ld -o $@ $< $(OBJDIR)/libbios.a --defsym=BIOS_SIZE=$$(llvm-objdump --section-headers $(OBJDIR)/apple2e.o | gawk --non-decimal-data '/ [0-9]+/ { size[$$2] = ("0x"$$3)+0 } END { print(size[".text"] + size[".data"] + size[".bss"]) }')
	
$(OBJDIR)/%.exe: $(OBJDIR)/src/bios/%.o $(OBJDIR)/libbios.a scripts/%.ld
	@mkdir -p $(dir $@)
	ld.lld -Map $(patsubst %.exe,%.map,$@) -T scripts/$*.ld -o $@ $< $(OBJDIR)/libbios.a $(LINKFLAGS)

$(OBJDIR)/4x8font.inc: bin/fontconvert third_party/tomsfonts/atari-small.bdf
	@mkdir -p $(dir $@)
	bin/fontconvert third_party/tomsfonts/atari-small.bdf > $@
	
$(OBJDIR)/bbcmicrofs.img: $(APPS) $(OBJDIR)/ccp.sys
	mkfs.cpm -f bbc192 $@
	cpmcp -f bbc192 $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f bbc192 $@ s 0:ccp.sys

bbcmicro.ssd: $(OBJDIR)/bbcmicro.exe $(OBJDIR)/bdos.img Makefile $(OBJDIR)/bbcmicrofs.img $(OBJDIR)/mkdfs
	$(OBJDIR)/mkdfs -O $@ \
		-N CP/M-65 \
		-f $(OBJDIR)/bbcmicro.exe -n \!boot -l 0x400 -e 0x400 -B 2 \
		-f $(OBJDIR)/bdos.img -n bdos \
		-f $(OBJDIR)/bbcmicrofs.img -n cpmfs

c64.d64: $(OBJDIR)/c64.exe $(OBJDIR)/bdos.img Makefile $(APPS) $(OBJDIR)/ccp.sys \
		$(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/c64.exe \
		-r 18 -s 1 -f bdos -w $(OBJDIR)/bdos.img \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f c1541 $@ s 0:ccp.sys 0:ccp.sys

$(OBJDIR)/generic-1m-cpmfs.img: $(OBJDIR)/bdos.img $(APPS) $(OBJDIR)/ccp.sys
	@rm -f $@
	mkfs.cpm -f generic-1m $@
	cpmcp -f generic-1m $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f generic-1m $@ s 0:ccp.sys

x16.zip: $(OBJDIR)/x16.exe $(OBJDIR)/bdos.img $(OBJDIR)/generic-1m-cpmfs.img
	@rm -f $@
	zip -9 $@ -j $^
	printf "@ x16.exe\n@=CPM\n" | zipnote -w $@
	printf "@ bdos.img\n@=BDOS\n" | zipnote -w $@
	printf "@ generic-1m-cpmfs.img\n@=CPMFS\n" | zipnote -w $@

$(OBJDIR)/apple2e.bios.swapped: $(OBJDIR)/apple2e.bios bin/shuffle
	bin/shuffle -i $< -o $@ -b 256 -t 16 -r -m 02468ace13579bdf

$(OBJDIR)/apple2e.boottracks: $(OBJDIR)/apple2e.bios.swapped $(OBJDIR)/bdos.img
	cp $(OBJDIR)/apple2e.bios.swapped $@
	truncate -s 4096 $@
	cat $(OBJDIR)/bdos.img >> $@

apple2e.po: $(OBJDIR)/apple2e.boottracks $(OBJDIR)/bdos.img $(APPS) $(OBJDIR)/ccp.sys Makefile diskdefs bin/shuffle
	@rm -f $@
	mkfs.cpm -f appleiie -b $(OBJDIR)/apple2e.boottracks $@
	cpmcp -f appleiie $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f appleiie $@ s 0:ccp.sys 0:cbm.sys
	truncate -s 143360 $@

$(OBJDIR)/pet.exe: LINKFLAGS += --no-check-sections
pet.d64: $(OBJDIR)/pet.exe $(OBJDIR)/bdos.img Makefile $(APPS) $(OBJDIR)/ccp.sys \
		$(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -i 15 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/pet.exe \
		-r 18 -s 1 -f bdos -w $(OBJDIR)/bdos.img \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f c1541 $@ s 0:ccp.sys 0:ccp.sys

$(OBJDIR)/vic20.exe: LINKFLAGS += --no-check-sections
$(OBJDIR)/src/bios/vic20.o: $(OBJDIR)/4x8font.inc
vic20.d64: $(OBJDIR)/vic20.exe $(OBJDIR)/bdos.img Makefile $(APPS) \
		$(OBJDIR)/ccp.sys $(OBJDIR)/mkcombifs
	@rm -f $@
	cc1541 -i 15 -q -n "cp/m-65" $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/vic20.exe \
		-r 18 -s 1 -f bdos -w $(OBJDIR)/bdos.img \
		$@
	$(OBJDIR)/mkcombifs $@
	cpmcp -f c1541 $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f c1541 $@ s 0:cbmfs.sys 0:ccp.sys

clean:
	rm -rf $(OBJDIR) bin apple2e.po c64.d64 bbcmicro.ssd x16.zip pet.d64 vic20.d64

.DELETE_ON_ERROR:
.SECONDARY:

