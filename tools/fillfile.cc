#include <stdio.h>
#include <unistd.h>
#include <fstream>
#include <fmt/format.h>

static std::string filename;
static int byteCount;
static int byteValue;

static void parseArgs(int argc, char* argv[])
{
    for (;;)
    {
        switch (getopt(argc, argv, "f:n:b:"))
        {
            case -1:
                return;

            case 'f':
                filename = optarg;
                break;

            case 'n':
                byteCount = strtol(optarg, nullptr, 0);
                break;

            case 'b':
                byteValue = strtol(optarg, nullptr, 0);
                break;

            default:
                fmt::print(stderr,
                    "Usage: fillfile -f <img> -n <count> -b <byte>\n");
                exit(1);
        }
    }
}

int main(int argc, char* argv[])
{
    parseArgs(argc, argv);

    std::ofstream of(filename);
    if (!of)
    {
        fmt::print(stderr,
            "fillfile: cannot open output file: {}\n", strerror(errno));
        exit(1);
    }

    for (int i=0; i<byteCount; i++)
        of.put(byteValue);

    of.close();
    return 0;
}
