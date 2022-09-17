CXX = g++
CA65 = ca65
LD65 = ld65

all: tools/multilink boot.img test.com bdos.img

tools/multilink: tools/multilink.cc
	$(CXX) -Os -g -o $@ $< -lfmt

%.o: %.s include/zif.inc include/mos.inc include/cpm65.inc
	$(CA65) -o $@ $< -I include --listing $(patsubst %.o,%.lst,$@)

boot.img: src/boot.o scripts/boot.cfg
	$(LD65) -C scripts/boot.cfg -o $@ $<
	
test.com: test.o tools/multilink
	tools/multilink -o $@ $<

bdos.img: src/bdos.o tools/multilink
	tools/multilink -o $@ $<

