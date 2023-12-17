/* Rearranges blocks in a file. Used for doing sector remapping.
 */

#include <stdio.h>
#include <unistd.h>
#include <ctype.h>
#include <string>
#include <iostream>
#include <fstream>
#include <sstream>
#include <map>
#include <fmt/format.h>

static int blocksize = 256;
static int blockspertrack = 16;
static std::string mappingstring = "0123456789abcdef";
static std::string infilename;
static std::string outfilename;
static bool reverse = false;
static bool verbose = false;

static std::string readfile(std::ifstream& in)
{
    std::ostringstream sstr;
    sstr << in.rdbuf();
    return sstr.str();
}

static int chartoint(char c)
{
    if (isdigit(c))
        return c - '0';
    c = tolower(c);
    if (isalpha(c))
        return 10 + c - 'a';
    std::cerr << "bad mapping string\n";
    exit(1);
}

static void write_file()
{
    std::ifstream ifs(infilename, std::ios::binary);
    std::ofstream ofs(outfilename, std::ios::binary);

    std::string infile = readfile(ifs);
    if (!ifs)
    {
        perror("Could not read input file");
        exit(1);
    }

    int inblocks = (infile.size() + blocksize - 1) / blocksize;
    int tracks = (inblocks + blockspertrack - 1) / blockspertrack;
    if (verbose)
        fmt::print(
            "file size: {} tracks of {} blocks\n", tracks, blockspertrack);
    infile.resize(tracks * blockspertrack * blocksize);

    std::map<int, int> mapping;
    for (int i = 0; i < mappingstring.size(); i++)
    {
        if (reverse)
            mapping[i] = chartoint(mappingstring[i]);
        else
            mapping[chartoint(mappingstring[i])] = i;
    }

    for (int track = 0; track < tracks; track++)
    {
        int baseblock = track * blockspertrack;
        for (int block = 0; block < blockspertrack; block++)
            ofs << infile.substr(
                (baseblock + mapping[block]) * blocksize, blocksize);
    }

    if (!ofs)
    {
        perror("Could not write output file");
        exit(1);
    }
}

int main(int argc, char* const argv[])
{
    for (;;)
    {
        switch (getopt(argc, argv, "b:t:m:i:o:r"))
        {
            case -1:
                write_file();
                return 0;

            case 'b':
                blocksize = std::stoi(optarg, nullptr, 0);
                break;

            case 't':
                blockspertrack = std::stoi(optarg, nullptr, 0);
                break;

            case 'm':
                mappingstring = optarg;
                break;

            case 'i':
                infilename = optarg;
                break;

            case 'o':
                outfilename = optarg;
                break;

            case 'r':
                reverse = true;
                break;

            case 'v':
                verbose = true;
                break;

            default:
                fprintf(stderr,
                    "Usage: shuffle -i <infile> -o <outfile> -b <blocksize> -t "
                    "<blocks per track> -m <mapping string> [-v] [-r]\n");
                exit(1);
        }
    }
}
