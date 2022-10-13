CXX = g++

CFLAGS65 = -Os

OBJDIR = .obj

APPS = \
	$(OBJDIR)/dump.com \
	$(OBJDIR)/submit.com \
	$(OBJDIR)/stat.com \
	$(OBJDIR)/rawdisk.com \
	cpmfs/readme.txt

LIBCPM_OBJS = \
	$(OBJDIR)/lib/printi.o \
	$(OBJDIR)/lib/bdos.o \
	$(OBJDIR)/lib/xfcb.o \

all: c64.d64 bbcmicro.ssd

$(OBJDIR)/multilink: tools/multilink.cc
	@mkdir -p $(dir $@)
	$(CXX) -Os -g -o $@ $< -lfmt

$(OBJDIR)/mkdfs: tools/mkdfs.c
	@mkdir -p $(dir $@)
	$(CXX) -Os -g -o $@ $<

$(OBJDIR)/%.o: %.S include/zif_llvm.inc include/mos.inc include/cpm65_llvm.inc
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -c -o $@ $< -I include

$(OBJDIR)/libxfcb.a: $(LIBXFCB_OBJS)
	@mkdir -p $(dir $@)
	$(AR65) r $@ $^

$(OBJDIR)/libcpm.a: $(LIBCPM_OBJS)
	@mkdir -p $(dir $@)
	llvm-ar rs $@ $^

$(OBJDIR)/c64.exe: $(OBJDIR)/src/c64.o $(OBJDIR)/src/relocate.o scripts/c64.ld
	@mkdir -p $(dir $@)
	ld.lld -Map $(patsubst %.exe,%.map,$@) -T scripts/c64.ld -o $@ \
		$(OBJDIR)/src/c64.o \
		$(OBJDIR)/src/relocate.o \
	
$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -c -I. -o $@ $^

$(OBJDIR)/%.com: $(OBJDIR)/apps/%.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/%.com: $(OBJDIR)/cc65/apps/%.o $(OBJDIR)/multilink $(OBJDIR)/libxfcb.a
	$(OBJDIR)/multilink -o $@ $< $(OBJDIR)/libxfcb.a

$(OBJDIR)/bdos.img: $(OBJDIR)/src/bdos.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/ccp.sys: $(OBJDIR)/src/ccp.o $(OBJDIR)/libcpm.a
	@mkdir -p $(dir $@)
	mos-cpm65-clang $(CFLAGS65) -I. -o $@ $^

$(OBJDIR)/bbcmicro.exe: $(OBJDIR)/src/bbcmicro.o $(OBJDIR)/src/relocate.o scripts/bbcmicro.ld
	@mkdir -p $(dir $@)
	ld.lld -Map $(patsubst %.exe,%.map,$@) -T scripts/bbcmicro.ld -o $@ \
		$(OBJDIR)/src/bbcmicro.o \
		$(OBJDIR)/src/relocate.o \
	
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
	-cpmcp -f c1541 $@ cpmfs/yeses 0:
	cpmchattr -f c1541 $@ s 0:ccp.sys 0:cbm.sys

clean:
	rm -rf $(OBJDIR) c64.d64 bbcmicro.ssd

.DELETE_ON_ERROR:
.SECONDARY:

