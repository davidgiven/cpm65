#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

/** Atari disk image header. All fields are little endian.
 *  The original ATR specification is kept to here, avoiding some of the
 *  less compatible AtariMax extensions to the format. */
struct ATRHeader
{
    /** Magic number, always set to 0x0296 */
    uint16_t magic;

    /** Size of the disk image in 'paragraphs'.
     *  A Paragraph is a 16 byte block. */
    uint16_t size;

    /** Size in bytes of a sector in the image.
     * 128 for single density and enhanced density
     * 256 for double density.
     * No matter the setting, the first 3 sectors should be 128 bytes long. */
    uint16_t sector_size;

    /** The high part of the size in paragraphs. */
    uint16_t size_high;

    /** Holds flags to indicate copy protection, write protect, etc. */
    uint8_t flags;

    /** Used for copy protection schemes. */
    uint16_t first_bad_sector;

    uint8_t unused[5];
};

struct ATRHeader *ATRHeader_new(uint32_t size_paragraphs,
                                uint16_t sector_size)
{
    struct ATRHeader *header;
    header = (struct ATRHeader*) malloc(sizeof(struct ATRHeader));

    header->magic = 0x0296;
    header->size = size_paragraphs & 0xFFFF;
    header->size_high = size_paragraphs >> 16;
    header->sector_size = sector_size;
    header->flags = 0;
    header->first_bad_sector = 0x0;

    for(int i=0; i < 5; i++)
    {
        header->unused[i] = 0;
    }


    return header;
}

int write_uint8(uint8_t val, FILE *f)
{
    return fwrite(&val, sizeof(uint8_t), 1, f);
}

int write_uint16_le(uint16_t val, FILE *f)
{
    uint8_t out[2];
    out[0] = val & 0xFF;
    out[1] = val >> 8;
    return fwrite(&val, sizeof(uint8_t), 1, f);
}

void ATRHeader_write(struct ATRHeader *header, FILE *f)
{
    write_uint16_le(header->magic, f);
    write_uint16_le(header->size, f);
    write_uint16_le(header->sector_size, f);
    write_uint16_le(header->size_high, f);
    write_uint8(header->flags, f);
    write_uint16_le(header->first_bad_sector, f);

    for(int i = 0; i < 5; i++)
    {
        write_uint8(header->unused[i], f);
    }
}

/**
 *  Write the boot record to the first sector of the disk.
 *      num_sectors: number of sectors that the OS will load
 *      load_address: the address that the boot record will be loaded to
 *      init_address: the address that will be jumped to after a RET from the
 *          boot sector.
 */
void write_boot_record(uint8_t num_sectors, uint16_t load_address,
                       uint16_t init_address, FILE *f)
{
    /* First byte is always zero */
    write_uint8(0x0, f);

    write_uint8(num_sectors, f);
    write_uint16_le(load_address, f);
    write_uint16_le(init_address, f);
}

uint32_t write_boot_sectors(const uint8_t* data, size_t size,
                            uint16_t load_address, uint16_t init_address,
                            FILE* f)
{
    size_t boot_record_size = 6;
    size_t total_size = boot_record_size = size;

    // Pad out to the nearest sector
    size_t padding = (0x80 - (total_size & 0x80)) & 0x7F;
    uint32_t num_sectors = (total_size + padding) / 128;

    write_boot_record(num_sectors, load_address, init_address, f);
    fwrite(data, sizeof(uint8_t), size, f);

    if(padding > 0) {
        uint8_t* padding_bytes = (uint8_t *) calloc(padding, sizeof(uint8_t));
        fwrite(padding_bytes, sizeof(uint8_t), padding, f);
        free(padding_bytes);
    }

    return num_sectors;
}

size_t round_nearest_sector(size_t size)
{
    return ((0x80 - (size & 0x80)) & 0x7F) + size;
}

int write_disk_image(uint8_t* boot_sector_data, size_t boot_sector_size,
    uint8_t* disk_data, size_t disk_data_size, uint16_t load_address,
    uint16_t init_address, uint32_t disk_size, FILE* output_file)
{
    size_t total_size = 6 + round_nearest_sector(boot_sector_size)
        + round_nearest_sector(disk_size);

    if(total_size / 128 > disk_size)
    {
        fprintf(stderr, "Provided data is too large to fit on disk.\n");
        return 1;
    }

    return 0;
}

void print_usage()
{
    fprintf(stderr,
        "Usage:\n"
        "\tmkatr -b <boot_sector_path> -d <disk_data_path> -l <load_address>\n"
        "\t\t-i <init_address> -o <output_path> -s <disk_size_sectors>\n");
}

int parse_address(const char* address_str, uint16_t* address)
{
    uint16_t result = (uint16_t)strtol(address_str, NULL, 0);
    if (result == 0)
    {
        return 1;
    }
    *address = result;
    return 0;
}

int read_file(const char* path, uint8_t** data_ptr, size_t* size)
{
    FILE* fp;

    fp = fopen(path, "r");
    if (fp == NULL)
    {
        return 1;
    }

    fseek(fp, 0L, SEEK_END);
    *size = ftell(fp);
    fseek(fp, 0L, SEEK_SET);
    *data_ptr = (uint8_t*)malloc(sizeof(uint8_t) * (*size));

    if (*data_ptr == NULL)
    {
        return 1;
    }

    fclose(fp);
    return 0;
}

int main(int argc, char* const argv[])
{
    int c;
    uint16_t load_address = 0;
    uint16_t init_address = 0;

    uint8_t* boot_sector_data = NULL;
    size_t boot_sector_size = 0;
    uint8_t* disk_data = NULL;
    size_t disk_data_size = 0;
    FILE* output_file = NULL;

    unsigned int disk_size = 0;

    while ((c = getopt(argc, argv, "b:d:l:i:o:s:")) != -1)
    {
        switch (c)
        {
            case -1:
                return 0;
            case 'b':
                if (read_file(optarg, &boot_sector_data, &boot_sector_size))
                {
                    fprintf(stderr,
                        "Unable to open boot sector file at %s\n",
                        optarg);
                    exit(1);
                }

                break;
            case 'd':
                if (read_file(optarg, &disk_data, &disk_data_size))
                {
                    fprintf(stderr,
                        "Unable to open disk data file at %s\n",
                        optarg);
                    exit(1);
                }

                break;
            case 'l':
                if (parse_address(optarg, &load_address))
                {
                    fprintf(stderr, "Invalid load address: %s\n", optarg);
                    exit(1);
                }
                break;
            case 'i':
                if (parse_address(optarg, &init_address))
                {
                    fprintf(stderr, "Invalid init address: %s\n", optarg);
                    exit(1);
                }
                break;
            case 'o':
                output_file = fopen(optarg, "w");
                break;
            case 's':
                disk_size = strtoul(optarg, NULL, 0);
                break;
            default:
                print_usage();
                exit(1);
        }
    }

    if (boot_sector_data == NULL || disk_data == NULL ||
        load_address == 0 || init_address == 0 || output_file == NULL)
    {
        print_usage();
        exit(1);
    }

    if(disk_size == 0)
    {
        // If a disk size is not provided, output an "enhanced density" (130K)
        // disk compatible with an Atari 1050 drive.
        disk_size = 1040;
    } else if (disk_size > 0x20000) {
        // 16MiB (131072 128 byte sectors) max size
        fprintf(stderr, "Provided disk image size is too large.\n");
    }

    printf("%zu, %zu\n", boot_sector_size, disk_data_size);

    int rv = write_disk_image(boot_sector_data,
        boot_sector_size,
        disk_data,
        disk_data_size,
        load_address,
        init_address,
        disk_size,
        output_file);

    fclose(output_file);
    free(boot_sector_data);
    free(disk_data);

    return rv;
}
