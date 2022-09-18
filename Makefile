CXX = g++
CA65 = ca65
LD65 = ld65

OBJDIR = .obj
DISKFORMAT = bbc163

APPS = \
	cpmfs/nop.com

all: $(OBJDIR)/multilink bios.img bdos.img ccp.img cpmfs.img

$(OBJDIR)/multilink: tools/multilink.cc
	$(CXX) -Os -g -o $@ $< -lfmt

$(OBJDIR)/%.o: %.s include/zif.inc include/mos.inc include/cpm65.inc
	@mkdir -p $(dir $@)
	$(CA65) -o $@ $< -I include --listing $(patsubst %.o,%.lst,$@)

bios.img: $(OBJDIR)/src/bios.o scripts/bios.cfg
	$(LD65) -m $(patsubst %.img,%.map,$@) -vm -C scripts/bios.cfg -o $@ $<
	
cpmfs/%.com: $(OBJDIR)/apps/%.o $(OBJDIR)/multilink
	$(OBJDIR)/multilink -o $@ $<

bdos.img: $(OBJDIR)/src/bdos.o $(OBJDIR)/multilink
	$(OBJDIR)/multilink -o $@ $<

cpmfs/ccp.sys: $(OBJDIR)/src/ccp.o $(OBJDIR)/multilink
	$(OBJDIR)/multilink -o $@ $<

cpmfs.img: $(wildcard cpmfs/*) $(APPS) cpmfs/ccp.sys
	mkfs.cpm -f $(DISKFORMAT) $@
	cpmcp -f $(DISKFORMAT) $@ $^ 0:

clean:
	rm -rf $(OBJDIR) bios.img bdos.img

.DELETE_ON_ERROR:

