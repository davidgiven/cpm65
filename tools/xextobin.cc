/* Converts an Atari XEX file (emitted by mads) to a CP/M-65 .com file.
 */

#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <ctype.h>
#include <string>
#include <iostream>
#include <fstream>
#include <sstream>
#include <map>
#include <fmt/format.h>

static uint8_t ram[0x10000];
static uint16_t base = 0;
static uint16_t himem = 0;
static std::string outfilename;

template <typename... T>
void error(fmt::format_string<T...> fmt, T&&... args)
{
    fmt::print(stderr, "xextocom: ");
    fmt::print(stderr, fmt, args...);
    fputc('\n', stderr);
    exit(1);
}

static uint16_t readle16(std::istream& is)
{
    uint8_t lo = is.get();
    uint8_t hi = is.get();
    return lo | (hi << 8);
}

static void read_file(std::string filename)
{
    std::ifstream ifs(filename, std::ios::binary);
	if (!ifs)
        error("could not read input file: {}", strerror(errno));

    for (;;)
    {
        uint16_t header = readle16(ifs);
        if (ifs.tellg() == -1)
            break;
        switch (header)
        {
            case 0xffff:
            {
                uint16_t start = readle16(ifs);
                uint16_t end = readle16(ifs);
                if (start == 0x0000)
                    error("relocatable blocks are not supported");
                uint16_t len = (end - start) + 1;
                fmt::print("reading 0x{:04x} bytes to 0x{:04x}\n", len, start);
                ifs.read((char*)(ram + start), len);
                himem = std::max((int)himem, (int)end+1);
                break;
            }

            default:
                error("unsupported header 0x{:04x}\n", header);
        }
    }
}

static void write_file()
{
    uint16_t len = himem - base;
    fmt::print("writing 0x{:04x} bytes from 0x{:04x}\n", len, base);
    
    std::ofstream ofs(outfilename, std::ios::out | std::ios::binary);
    if (!ofs)
        error("failed to open output file: {}", strerror(errno));
    ofs.write((char*)(ram + base), len);
}

int main(int argc, char* const argv[])
{
    for (;;)
    {
        switch (getopt(argc, argv, "b:i:o:"))
        {
            case -1:
                write_file();
                return 0;

            case 'b':
                base = std::stoi(optarg, nullptr, 0);
                break;

            case 'i':
                read_file(optarg);
                break;

            case 'o':
                outfilename = optarg;
                break;

            default:
                fmt::print(stderr,
                    "Usage: xextobin -i <infile> -o <outfile> -b <base>\n");
                exit(1);
        }
    }
}

