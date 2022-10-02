/* CP/M-65 Copyright © 2022 David Given
 * This file is licensed under the terms of the 2-clause BSD license. Please
 * see the COPYING file in the root project directory for the full text.
 */

#define _XOPEN_SOURCE 500
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>

static const char* output_filename = "dfs.ssd";

static int boot_mode = 0;
static int disk_size = 800;
static int disk_pos = 2;
static char disk_name[12] = "Disk";

struct catalogue_entry
{
    const char* filename;
    char name[7];
    char directory;
    void* data;
    uint32_t startsector;
    uint32_t sectors;
    uint32_t length;
    uint32_t load_address;
    uint32_t exec_address;
};

static struct catalogue_entry catalogue[31];
static struct catalogue_entry* lastfile = NULL;
static int catalogue_pos = 0;

static void add_file(const char* filename)
{
    if (catalogue_pos == 32)
    {
        fprintf(stderr, "too many files\n");
        exit(1);
    }

    lastfile = &catalogue[catalogue_pos++];

    int fd = open(filename, O_RDONLY);
    if (fd == -1)
    {
        fprintf(stderr, "cannot open '%s': %s\n", filename, strerror(errno));
        exit(1);
    }

    struct stat st;
    fstat(fd, &st);
    lastfile->length = st.st_size;
    lastfile->load_address = lastfile->exec_address = 0xffffffff;
    lastfile->directory = '$';
    memset(&lastfile->name, ' ', 7);

    const char* leaf = strrchr(filename, '/');
    if (!leaf)
        leaf = filename;
    else
        leaf++;
    for (int i=0; i<7; i++)
    {
        char c = leaf[i];
        if ((c == '.') || (c == '\0'))
            break;
        lastfile->name[i] = c;
    }

    lastfile->sectors = ((st.st_size + 0xff) & ~0xff) >> 8;
    lastfile->startsector = disk_pos;
    disk_pos += lastfile->sectors;
    if (disk_pos > disk_size)
    {
        fprintf(stderr, "no space on disk\n");
        exit(1);
    }

    lastfile->data = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (lastfile->data == (void*)-1)
    {
        fprintf(stderr, "cannot load '%s': %s\n", filename, strerror(errno));
        exit(1);
    }
}

static void write_byte(int fd, uint32_t pos, uint8_t value)
{
    pwrite(fd, &value, 1, pos);
}

static void write_word(int fd, uint32_t pos, uint16_t value)
{
    write_byte(fd, pos, value);
    write_byte(fd, pos+1, value>>8);
}

static void write_quad(int fd, uint32_t pos, uint32_t value)
{
    write_word(fd, pos, value);
    write_word(fd, pos+2, value>>16);
}

static void write_disk(void)
{
    int fd = open(output_filename, O_WRONLY|O_CREAT|O_TRUNC, 0644);
    if (fd == -1)
    {
        fprintf(stderr, "cannot open output file: %s\n", strerror(errno));
        exit(1);
    }

    ftruncate(fd, disk_size * 0x100);
    write_byte(fd, 0x107, disk_size);
    write_byte(fd, 0x106, (boot_mode<<4) | (disk_size>>8));
    write_byte(fd, 0x105, catalogue_pos << 3);
    pwrite(fd, disk_name+0, 8, 0x000);
    pwrite(fd, disk_name+8, 4, 0x100);

    for (int i=0; i<catalogue_pos; i++)
    {
        struct catalogue_entry* ce = &catalogue[catalogue_pos - i - 1];
        pwrite(fd, ce->data, 0x100 * ce->sectors, ce->startsector * 0x100);
        pwrite(fd, ce->name, 7, 8 + i*8);
        write_byte(fd, 0x008 + i*8 + 7, ce->directory);
        write_word(fd, 0x108 + i*8 + 0, ce->load_address);
        write_word(fd, 0x108 + i*8 + 2, ce->exec_address);
        write_word(fd, 0x108 + i*8 + 4, ce->length);
        write_byte(fd, 0x108 + i*8 + 7, ce->startsector);

        write_byte(fd, 0x108 + i*8 + 6,
            (((ce->load_address >> 16) & 0x3) << 2) |
            (((ce->exec_address >> 16) & 3) << 6) |
            (((ce->length >> 16) & 3) << 4) |
            (ce->startsector >> 8));
    }

    close(fd);
}

int main(int argc, char* const argv[])
{
    for (;;)
    {
        switch (getopt(argc, argv, "O:S:N:B:f:n:l:e:"))
        {
            case -1:
                write_disk();
                return 0;

            case 'O':
                output_filename = optarg;
                break;

            case 'S':
                disk_size = atoi(optarg);
                break;

            case 'N':
                memset(disk_name, 0, sizeof(disk_name));
                strncpy(disk_name, optarg, sizeof(disk_name));
                break;

            case 'B':
                boot_mode = atoi(optarg);
                break;

            case 'f':
                add_file(optarg);
                break;

            case 'n':
                if ((optarg[0] != '\0') && (optarg[1] == '.'))
                {
                    lastfile->directory = optarg[0];
                    optarg = optarg + 2;
                }
                memset(&lastfile->name, ' ', 7);
                for (int i=0; i<7; i++)
                {
                    char c = optarg[i];
                    if (c == '\0')
                        break;
                    lastfile->name[i] = c;
                }
                break;

            case 'l':
                lastfile->load_address = strtoul(optarg, NULL, 0);
                if (lastfile->exec_address == 0xffffffff)
                    lastfile->exec_address = lastfile->load_address;
                break;

            case 'e':
                lastfile->exec_address = strtoul(optarg, NULL, 0);
                break;

            default:
                fprintf(stderr, "Usage: mkdfs -O <diskname> -f <filename> ...\n");
                exit(1);
        }
    }
}
