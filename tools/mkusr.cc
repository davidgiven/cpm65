/* Creates a Commodore DOS USR program. */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <fstream>
#include <fmt/format.h>
#include <gelf.h>

static std::string inputfilename;
static std::string outputfilename;

static void parseArgs(int argc, char* argv[])
{
    for (;;)
    {
        switch (getopt(argc, argv, "r:w:"))
        {
            case -1:
                return;

            case 'r':
                inputfilename = optarg;
                break;

            case 'w':
                outputfilename = optarg;
                break;

            default:
                fmt::print(
                    stderr, "Usage: mkusr -r <binary> -w <usr> -a <address>\n");
                exit(1);
        }
    }
}

static void ppread(int fd, uint8_t* buffer, size_t count, off_t offset)
{
    while (count)
    {
        ssize_t i = pread(fd, buffer, count, offset);
        if (i == -1)
        {
            perror("read filed");
            exit(1);
        }

        buffer += i;
        offset += i;
        count -= i;
    }
}

int main(int argc, char* argv[])
{
    parseArgs(argc, argv);

    std::ofstream ofs(outputfilename);
    if (!ofs)
    {
        fmt::print(
            stderr, "mkusr: cannot open output file: {}\n", strerror(errno));
        exit(1);
    }

    elf_version(EV_CURRENT);
    int fd = open(inputfilename.c_str(), O_RDONLY);
    Elf* e = elf_begin(fd, ELF_C_READ, nullptr);

    size_t phdrs;
    elf_getphdrnum(e, &phdrs);
    for (int i = 0; i < phdrs; i++)
    {
        GElf_Phdr phdr = {};
        gelf_getphdr(e, i, &phdr);
        if (phdr.p_type != PT_LOAD)
            continue;

        fmt::print("phdr {}, load={:x} off={:x} size={:x}\n",
            i,
            phdr.p_vaddr,
            phdr.p_offset,
            phdr.p_filesz);

        uint8_t buffer[phdr.p_filesz];
        ppread(fd, buffer, phdr.p_filesz, phdr.p_offset);

        int sum = 0;
        auto put = [&](uint8_t b)
        {
            sum += b;
            if (sum > 255)
                sum -= 255;
            ofs.put((char)b);
        };

        put(phdr.p_vaddr & 0xff);
        put(phdr.p_vaddr >> 8);
        put(phdr.p_filesz);
        for (uint8_t c : buffer)
            put(c);

        ofs.put(sum);
    }
    return 0;
}
