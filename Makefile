CXX = g++
CA65 = ca65
LD65 = ld65

OBJDIR = .obj

all: $(OBJDIR)/multilink bios.img test.com bdos.img

$(OBJDIR)/multilink: tools/multilink.cc
	$(CXX) -Os -g -o $@ $< -lfmt

$(OBJDIR)/%.o: %.s include/zif.inc include/mos.inc include/cpm65.inc
	@mkdir -p $(dir $@)
	$(CA65) -o $@ $< -I include --listing $(patsubst %.o,%.lst,$@)

bios.img: $(OBJDIR)/src/bios.o scripts/bios.cfg
	$(LD65) -C scripts/bios.cfg -o $@ $<
	
test.com: $(OBJDIR)/test.o $(OBJDIR)/multilink
	$(OBJDIR)/multilink -o $@ $<

bdos.img: $(OBJDIR)/src/bdos.o $(OBJDIR)/multilink
	$(OBJDIR)/multilink -o $@ $<

clean:
	rm -rf $(OBJDIR) bios.img bdos.img

