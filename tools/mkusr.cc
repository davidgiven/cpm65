/* Creates a Commodore DOS USR program. */

#include <stdio.h>
#include <unistd.h>
#include <fstream>
#include <fmt/format.h>

static std::string inputfilename;
static std::string outputfilename;
static uint16_t address;

static void parseArgs(int argc, char* argv[])
{
    for (;;)
    {
        switch (getopt(argc, argv, "r:w:a:"))
        {
            case -1:
                return;

            case 'r':
                inputfilename = optarg;
                break;

            case 'w':
                outputfilename = optarg;
                break;

            case 'a':
                address = strtol(optarg, nullptr, 0);
                break;

            default:
                fmt::print(
                    stderr, "Usage: mkusr -r <binary> -w <usr> -a <address>\n");
                exit(1);
        }
    }
}

int main(int argc, char* argv[])
{
    parseArgs(argc, argv);

    std::ifstream ifs(inputfilename);
    if (!ifs)
    {
        fmt::print(
            stderr, "mkusr: cannot open input file: {}\n", strerror(errno));
        exit(1);
    }

    std::ofstream ofs(outputfilename);
    if (!ofs)
    {
        fmt::print(
            stderr, "mkusr: cannot open output file: {}\n", strerror(errno));
        exit(1);
    }

    std::string buffer{
        std::istreambuf_iterator<char>(ifs), std::istreambuf_iterator<char>()};

    int sum = 0;
    auto put = [&](uint8_t b) {
        sum += b;
        if (sum > 255)
            sum -= 255;
        ofs.put((char)b);
    };

    put(address & 0xff);
    put(address >> 8);
    put(buffer.size());
    for (char c : buffer)
        put(c);
    
    ofs.put(sum);

    return 0;
}
