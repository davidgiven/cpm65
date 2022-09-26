CXX = g++
CA65 = ca65
LD65 = ld65
AR65 = ar65

OBJDIR = .obj
DISKFORMAT = bbc163

APPS = \
	cpmfs/dump.com \
	cpmfs/make.com \
	cpmfs/bitmap.com \

LIBXFCB_OBJS = \
	$(OBJDIR)/lib/xfcb/clear.o \
	$(OBJDIR)/lib/xfcb/close.o \
	$(OBJDIR)/lib/xfcb/erase.o \
	$(OBJDIR)/lib/xfcb/get.o \
	$(OBJDIR)/lib/xfcb/make.o \
	$(OBJDIR)/lib/xfcb/open.o \
	$(OBJDIR)/lib/xfcb/prepare.o \
	$(OBJDIR)/lib/xfcb/readseq.o \
	$(OBJDIR)/lib/xfcb/set.o \
	$(OBJDIR)/lib/xfcb/vars.o \
	$(OBJDIR)/lib/xfcb/writeseq.o \

all: $(OBJDIR)/multilink bios.img bdos.img cpmfs.img $(OBJDIR)/libxfcb.a

$(OBJDIR)/multilink: tools/multilink.cc
	@mkdir -p $(dir $@)
	$(CXX) -Os -g -o $@ $< -lfmt

$(OBJDIR)/%.o: %.s include/zif.inc include/mos.inc include/cpm65.inc
	@mkdir -p $(dir $@)
	$(CA65) -o $@ $< -I include -I lib/xfcb --listing $(patsubst %.o,%.lst,$@)

$(OBJDIR)/libxfcb.a: $(LIBXFCB_OBJS)
	@mkdir -p $(dir $@)
	$(AR65) r $@ $^

bios.img: $(OBJDIR)/src/bios.o scripts/bios.cfg
	$(LD65) -m $(patsubst %.img,%.map,$@) -vm -C scripts/bios.cfg -o $@ $<
	
cpmfs/%.com: $(OBJDIR)/apps/%.o $(OBJDIR)/multilink $(OBJDIR)/libxfcb.a
	$(OBJDIR)/multilink -o $@ $< $(OBJDIR)/libxfcb.a

bdos.img: $(OBJDIR)/src/bdos.o $(OBJDIR)/multilink
	$(OBJDIR)/multilink -o $@ $<

cpmfs/ccp.sys: $(OBJDIR)/src/ccp.o $(OBJDIR)/multilink $(OBJDIR)/libxfcb.a
	$(OBJDIR)/multilink -o $@ $< $(OBJDIR)/libxfcb.a

cpmfs.img: $(wildcard cpmfs/*) $(APPS) cpmfs/ccp.sys
	rm -f $@
	mkfs.cpm -f $(DISKFORMAT) $@
	cpmcp -f $(DISKFORMAT) $@ $^ 0:
	#cpmchattr -f $(DISKFORMAT) $@ s 0:ccp.sys

clean:
	rm -rf $(OBJDIR) bios.img bdos.img

.DELETE_ON_ERROR:

