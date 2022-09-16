CXX = g++

all: tools/multilink

tools/multilink: tools/multilink.cc
	$(CXX) -Os -g -o $@ $< -lfmt

