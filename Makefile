CXX = g++
CC = gcc

CFLAGS = -O0 -g -I.
CFLAGS65 = -Os -g

OBJDIR = .obj

APPS = \
	$(OBJDIR)/dump.com \
	$(OBJDIR)/submit.com \
	$(OBJDIR)/stat.com \
	$(OBJDIR)/copy.com \
	cpmfs/readme.txt \
	cpmfs/hello.asm \

LIBCPM_OBJS = \
	$(OBJDIR)/lib/printi.o \
	$(OBJDIR)/lib/bdos.o \
	$(OBJDIR)/lib/xfcb.o \

LIBBIOS_OBJS = \
	$(OBJDIR)/src/bios/relocate.o \
	$(OBJDIR)/src/bios/petscii.o \

CPMEMU_OBJS = \
	$(OBJDIR)/tools/cpmemu/main.o \
	$(OBJDIR)/tools/cpmemu/emulator.o \
	$(OBJDIR)/tools/cpmemu/fileio.o \
	$(OBJDIR)/tools/cpmemu/biosbdos.o \
	$(OBJDIR)/third_party/lib6502/lib6502.o \

all: c64.d64 bbcmicro.ssd x16.zip $(OBJDIR)/cpmemu

$(OBJDIR)/multilink: $(OBJDIR)/tools/multilink.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $< -lfmt

$(OBJDIR)/mkdfs: $(OBJDIR)/tools/mkdfs.o
	@mkdir -p $(dir $@)
	$(CXX) $(CFLAGS) -o $@ $<

$(OBJDIR)/cpmemu: $(CPMEMU_OBJS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $(CPMEMU_OBJS) -lreadline

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

$(OBJDIR)/bdos.img: $(OBJDIR)/src/bdos.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/ccp.sys: $(OBJDIR)/src/ccp.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/%.exe: $(OBJDIR)/src/bios/%.o $(OBJDIR)/libbios.a scripts/%.ld
	@mkdir -p $(dir $@)
	ld.lld -Map $(patsubst %.exe,%.map,$@) -T scripts/$*.ld -o $@ $< $(OBJDIR)/libbios.a
	
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

c64.d64: $(OBJDIR)/c64.exe $(OBJDIR)/bdos.img Makefile $(APPS) $(OBJDIR)/ccp.sys
	@rm -f $@
	cc1541 -q -n "cp/m-65" $@
	mkfs.cpm -f c1541 $@
	cc1541 -q \
		-t -u 0 \
		-r 18 -f cpm -w $(OBJDIR)/c64.exe \
		-r 18 -s 1 -f bdos -w $(OBJDIR)/bdos.img \
		$@
	cpmcp -f c1541 $@ /dev/null 0:cbm.sys
	echo "00f: 30 59 5a 5b 5c 5d 5e" | xxd -r - $@
	echo "16504: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16514: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16524: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16534: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16544: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16554: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16564: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16574: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	echo "16584: 00 00 00 00 00 00 00 00 00 00 00 00" | xxd -r - $@
	cpmcp -f c1541 $@ $(OBJDIR)/ccp.sys $(APPS) 0:
	cpmchattr -f c1541 $@ s 0:ccp.sys 0:cbm.sys

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

clean:
	rm -rf $(OBJDIR) c64.d64 bbcmicro.ssd x16.zip

.DELETE_ON_ERROR:
.SECONDARY:

