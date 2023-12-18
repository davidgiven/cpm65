#include <stdlib.h>
#include <fmt/format.h>
#include <fstream>
#include <set>
#include <filesystem>
#include <assert.h>
#include <unistd.h>

/* Does the magic fixing up to make a combination 1541/CPMFS disk.
 *
 * This should be run after using c1541 to create the disk and write files to
 * it.  It will then read the BAM to find out which blocks are in use and
 * create a CPMFS filesystem with a magic CBMFS.SYS file covering those blocks.
 * The 1541 filesystem will then be updated so that the BAM thinks that all
 * blocks are in use.
 */

static std::string infilename;
static bool verbose = false;

template <typename... T>
void error(fmt::format_string<T...> fmt, T&&... args)
{
    fmt::print(stderr, fmt, args...);
    fputc('\n', stderr);
    exit(1);
}

static int get1541TrackSize(int track)
{
    if (track <= 17)
        return 21;
    if (track <= 24)
        return 19;
    if (track <= 30)
        return 18;
    return 17;
}

/* 1-offset track numbers! But 0-offset sector numbers... */
static int get1541LBA(int track, int sector)
{
    int offset = 0;

    assert(track != 0);
    for (int t = 1; t < track; t++)
        offset += get1541TrackSize(t);

    return offset + sector;
}

static void syntaxError()
{
    fmt::print(stderr, "Usage: mkcombifs [-v] <file>\n");
    exit(1);
}

static void parseArguments(int argc, char* const* argv)
{
    for (;;)
    {
        switch (getopt(argc, argv, "vf:"))
        {
            case -1:
                if (infilename.empty() || argv[optind])
                    syntaxError();

            case 'f':
                infilename = optarg;
                return;

            case 'v':
                verbose = true;
                break;

            default:
                syntaxError();
        }
    }
}

int main(int argc, char* const* argv)
{
    parseArguments(argc, argv);

    std::fstream fs(
        infilename, std::ios::binary | std::ios::in | std::ios::out);
    if (!fs)
        error("Cannot open input file: {}", strerror(errno));
    uint32_t size = std::filesystem::file_size(infilename);

    uint8_t bam[256];
    fs.seekg(get1541LBA(18, 0) * 256);
    fs.read((char*)bam, sizeof(bam));

    if (bam[2] != 0x41)
        error("This doesn't look like a 1541 file system");

    std::set<int> usedSectors;

    for (int track = 1;; track++)
    {
        int offset = get1541LBA(track, 0) * 256;
        if (offset >= size)
            break;

        uint8_t* bamp = &bam[5 + (track - 1) * 4];
        uint32_t bitmap = bamp[0] | (bamp[1] << 8) | (bamp[2] << 16);
        int sectorCount = get1541TrackSize(track);

        for (int sector = 0; sector < sectorCount; sector++)
        {
            bool allocated = !(bitmap & 1);
            bitmap >>= 1;

            if (allocated)
                usedSectors.insert(get1541LBA(track, sector));
        }

        bamp[-1] = bamp[0] = bamp[1] = bamp[2] = 0;
    }
    if (verbose)
        fmt::print(
            "1541 filesystem has {} allocated sectors\n", usedSectors.size());

    std::set<int> usedBlocks;
    for (int sector : usedSectors)
        usedBlocks.insert(sector / 4);

    if (verbose)
        fmt::print(
            "CP/M filesystem has {} allocated blocks\n", usedBlocks.size());

    for (int i = 0; i < 64; i++)
    {
        fs.seekp(32 * i);
        for (int j = 0; j < 32; j++)
            fs.put(0xe5);
    }

    uint8_t dirent[32] = {0,
        'C',
        'B',
        'M',
        'F',
        'S',
        ' ',
        ' ',
        ' ',
        'S' | 0x80,
        'Y' | 0x80,
        'S',
        /* EX */ 0,
        /* S1 */ 0,
        /* S2 */ 0,
        /* RC */ (uint8_t)(usedBlocks.size() * 8)};
    uint8_t* al = &dirent[16];
    for (int block : usedBlocks)
        *al++ = block;
    fs.seekp(0);
    fs.write((const char*)dirent, sizeof(dirent));

    fs.seekp(get1541LBA(18, 0) * 256);
    fs.write((char*)bam, sizeof(bam));

    return 0;
}
