#define _XOPEN_SOURCE 500
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <glob.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <libelf.h>
#include <gelf.h>
#include "globals.h"

static uint16_t dma;
static uint8_t current_disk;
static int exitcode = 0;
uint16_t himem = BDOS_ADDRESS;

static const char* bdos_names[] = {
    "BDOS_EXIT_PROGRAM",
    "BDOS_CONSOLE_INPUT",
    "BDOS_CONSOLE_OUTPUT",
    "BDOS_AUX_INPUT",
    "BDOS_AUX_OUTPUT",
    "BDOS_PRINTER_OUTPUT",
    "BDOS_DIRECT_IO",
    "BDOS_GET_IO_BYTE",
    "BDOS_SET_IO_BYTE",
    "BDOS_WRITE_STRING",
    "BDOS_READ_LINE",
    "BDOS_CONSOLE_STATUS",
    "BDOS_GET_VERSION",
    "BDOS_RESET_DISKS",
    "BDOS_SELECT_DISK",
    "BDOS_OPEN_FILE",
    "BDOS_CLOSE_FILE",
    "BDOS_FIND_FIRST",
    "BDOS_FIND_NEXT",
    "BDOS_DELETE_FILE",
    "BDOS_READ_SEQUENTIAL",
    "BDOS_WRITE_SEQUENTIAL",
    "BDOS_CREATE_FILE",
    "BDOS_RENAME_FILE",
    "BDOS_GET_LOGIN_BITMAP",
    "BDOS_GET_CURRENT_DRIVE",
    "BDOS_SET_DMA_ADDRESS",
    "BDOS_GET_ALLOCATION_BITMAP",
    "BDOS_SET_DRIVE_READONLY",
    "BDOS_GET_READONLY_BITMAP",
    "BDOS_SET_FILE_ATTRIBUTES",
    "BDOS_GET_DPB",
    "BDOS_GET_SET_USER_NUMBER",
    "BDOS_READ_RANDOM",
    "BDOS_WRITE_RANDOM",
    "BDOS_COMPUTE_FILE_SIZE",
    "BDOS_COMPUTE_RANDOM_POINTER",
    "BDOS_RESET_DISK",
    "BDOS_GET_BIOS",
    "BDOS_39",
    "BDOS_WRITE_RANDOM_FILLED",
    "BDOS_GETZP",
    "BDOS_GETTPA",
    "BDOS_PARSEFILENAME",
};

struct fcb
{
    cpm_filename_t filename; /* includes drive */
    uint8_t extent;
    uint8_t s1;
    uint8_t s2;
    uint8_t recordcount;
    uint8_t d[16];
    uint8_t currentrecord;
    uint8_t r[3];
};

static void bios_getchar(void);
static struct fcb* fcb_at(uint16_t address);

static uint16_t get_xa(void)
{
    return (cpu->registers->x << 8) | cpu->registers->a;
}

static void set_xa(uint16_t xa)
{
    cpu->registers->x = xa >> 8;
    cpu->registers->a = xa;
}

static void set_result(uint16_t xa, bool succeeded)
{
    set_xa(xa);
    if (succeeded)
        cpu->registers->p &= ~0x01;
    else
        cpu->registers->p |= 0x01;
}

void bios_coldboot(void) {}

static uint16_t do_relocation_item(uint16_t address, uint8_t n, uint8_t addend)
{
    address += n;
    if (n != 0xe)
        ram[address] += addend;
    return address;
}

static uint16_t do_relocation(uint16_t relotable, uint8_t addend)
{
    uint16_t address = TPA_BASE;
    for (;;)
    {
        uint8_t b = ram[relotable++];
        uint8_t msb = b >> 4;
        if (msb == 0xf)
            return relotable;
        address = do_relocation_item(address, msb, addend);

        uint8_t lsb = b & 0xf;
        if (lsb == 0xf)
            return relotable;
        address = do_relocation_item(address, lsb, addend);
    }
}

static void relocate(uint16_t relotable)
{
    relotable = do_relocation(relotable, ZP_BASE);
    do_relocation(relotable, TPA_BASE >> 8);
}

static void makefcb(uint16_t address, const char* word)
{
    if (!word)
        word = "";

    struct fcb* fcb = fcb_at(address);
    memset(fcb, 0, sizeof(struct fcb));
    memset(fcb->filename.bytes, ' ', 11);

    if (word[0] && (word[1] == ':'))
    {
        fcb->filename.drive = toupper(word[0]) - '@';
        word += 2;
    }

    int offset = 0;
    while (offset < 8)
    {
        uint8_t c = toupper(*word++);
        if (!c)
            break;
        if (c == '.')
            break;
        fcb->filename.bytes[offset++] = c;
    }

    if (*word == '.')
        word++;
    if (offset && (word[-1] == '.'))
    {
        offset = 8;
        while (offset < 11)
        {
            uint8_t c = toupper(*word++);
            if (!c)
                break;
            fcb->filename.bytes[offset++] = c;
        }
    }
}

static void load_binary(std::string filename)
{
    /* Load the binary. */

    int fd = open(filename.c_str(), O_RDONLY);
    if (fd == -1)
        fatal("couldn't open program: %s", strerror(errno));
    read(fd, &ram[TPA_BASE], himem - TPA_BASE);
    close(fd);

    /* If an ELF file exists, fetch symbol information from it. */

    std::string elffilename = filename + ".elf";
    if (access(elffilename.c_str(), R_OK) == 0)
    {
        /* ELF file exists; load from this. */

        elf_version(EV_NONE);
        if (elf_version(EV_CURRENT) == EV_NONE)
            fatal("bad libelf versrion");

        int fd = open(elffilename.c_str(), O_RDONLY);
        if (fd == -1)
            fatal("couldn't open program: %s", strerror(errno));
        Elf* elf = elf_begin(fd, ELF_C_READ, nullptr);
        if ((elf_kind(elf) != ELF_K_ELF))
            fatal("not an ELF file");

        GElf_Phdr phdr;
        if ((gelf_getphdr(elf, 0, &phdr) != &phdr) || (phdr.p_type != PT_LOAD))
            fatal("could not fetch main data block from ELF file: %s",
                elf_errmsg(-1));

        uint16_t loadAddress = phdr.p_vaddr;

        Elf_Scn* scn = nullptr;
        GElf_Shdr shdr;
        for (;;)
        {
            scn = elf_nextscn(elf, scn);
            if (!scn)
                break;

            gelf_getshdr(scn, &shdr);
            if (shdr.sh_type == SHT_SYMTAB)
            {
                Elf_Data* data = elf_getdata(scn, NULL);
                int count = shdr.sh_size / shdr.sh_entsize;

                /* print the symbol names */
                for (int i = 0; i < count; ++i)
                {
                    GElf_Sym sym;
                    gelf_getsym(data, i, &sym);

                    std::string name =
                        elf_strptr(elf, shdr.sh_link, sym.st_name);
                    uint16_t address = sym.st_value;
                    if (address >= loadAddress)
                    {
                        address -= loadAddress;
                        address += TPA_BASE;
                    }

                    symbolsByName[name] = address;
                    symbolsByAddress[address] = name;
                }
            }
        }

        elf_end(elf);
        close(fd);
    }
}

void bios_warmboot(void)
{
    M6502_reset(cpu);

    if (user_command_line[0])
    {
        static bool terminate_next_time = false;
        if (terminate_next_time)
            exit(exitcode);
        terminate_next_time = true;

        /* Push the return address onto the stack. */
        ram[0x01fe] = (EXIT_ADDRESS - 1) & 0xff;
        ram[0x01ff] = (EXIT_ADDRESS - 1) >> 8;
        cpu->registers->s = 0xfd;

        load_binary(user_command_line[0]);

        uint16_t relotable =
            (ram[TPA_BASE + 2] | (ram[TPA_BASE + 3] << 8)) + TPA_BASE;
        relocate(relotable);

        /* Parse the first word of the command line into the primary FCB. */

        makefcb(relotable, user_command_line[1]);
        if (user_command_line[1])
            makefcb(relotable + 16, user_command_line[2]);

        /* Generate the command line. */

        dma = relotable + 37; /* leave space for the FCBs */

        int offset = 1;
        for (int word = 1; user_command_line[word]; word++)
        {
            if (word > 1)
            {
                ram[dma + offset] = ' ';
                offset++;
            }

            const char* pin = user_command_line[word];
            while (*pin)
            {
                if (offset > 125)
                    fatal("user command line too long");
                ram[dma + offset] = toupper(*pin++);
                offset++;
            }
        }
        ram[dma] = offset - 1;
        ram[dma + offset] = 0xe5; /* deliberately not zero-terminated */

        ram[TPA_BASE + 5] = BDOS_ADDRESS & 0xff;
        ram[TPA_BASE + 6] = BDOS_ADDRESS >> 8;
        cpu->registers->pc = TPA_BASE + 7;
    }
    else
    {
        fatal("CCP not supported in this version");
    }
}

static void bios_const(void)
{
    struct pollfd pollfd = {0, POLLIN, 0};
    poll(&pollfd, 1, 0);
    if (pollfd.revents & POLLIN)
        set_result(0xff, true);
    else
        set_result(0, true);
}

static void bios_getchar(void)
{
    char c = 0;
    (void)read(0, &c, 1);
    if (c == '\n')
        c = '\r';
    set_result(c, true);
}

static void bios_putchar(void)
{
    (void)write(1, &cpu->registers->a, 1);
}

void bios_entry(uint8_t bios_call)
{
    switch (bios_call)
    {
            // clang-format off
        case 0: bios_coldboot(); return;
        case 1: bios_warmboot(); return;
        case 2: bios_const(); return; // const
        case 3: bios_getchar(); return; // conin
        case 4: bios_putchar(); return; // conout
		case 9: set_result((TPA_BASE>>8) | (himem&0xff00), true); return;
            // clang-format on
    }

    showregs();
    fatal("unimplemented bios entry %d", bios_call);
}

static void bdos_getchar(void)
{
    bios_getchar();
}

static void bdos_putchar(void)
{
    uint8_t c = cpu->registers->a;
    (void)write(1, &c, 1);
}

static void bdos_consoleio(void)
{
    uint8_t c = cpu->registers->a;
    if (c == 0xff)
    {
        bios_const();
        if (cpu->registers->a == 0xff)
            bios_getchar();
    }
    else
        bdos_putchar();
}

static void bdos_printstring(void)
{
    uint16_t xa = get_xa();
    for (;;)
    {
        uint8_t c = ram[xa++];
        if (!c || (c == '$'))
            break;
        (void)write(1, &c, 1);
    }
}

static void bdos_consolestatus(void)
{
    bios_const();
    set_result(cpu->registers->a, true);
}

void bdos_readline(void)
{
    fflush(stdout);

    uint16_t xa = get_xa();
    uint8_t maxcount = ram[xa + 0];
    int count = read(0, &ram[xa + 2], maxcount);
    if ((count > 0) && (ram[xa + 2 + count - 1] == '\n'))
        count--;
    ram[xa + 1] = count;
    set_result(count, true);
}

static struct fcb* fcb_at(uint16_t address)
{
    struct fcb* fcb = (struct fcb*)&ram[address];

    /* Autoselect the current drive. */
    if (fcb->filename.drive == 0)
        fcb->filename.drive = current_disk + 1;

    return fcb;
}

static struct fcb* find_fcb(void)
{
    return fcb_at(get_xa());
}

static int get_current_record(struct fcb* fcb)
{
    return (fcb->extent * 128) + fcb->currentrecord;
}

static void set_current_record(struct fcb* fcb, int record, int total)
{
    int extents = total / 128;
    fcb->extent = record / 128;
    if (fcb->extent < extents)
        fcb->recordcount = 128;
    else
        fcb->recordcount = total % 128;
    fcb->currentrecord = record % 128;
}

static void bdos_resetdisk(void)
{
    current_disk = 0; /* select drive A */
    set_result(0xff, true);
}

static void bdos_selectdisk(void)
{
    current_disk = cpu->registers->a;
}

static void bdos_getdisk(void)
{
    set_result(current_disk, true);
}

static void bdos_openfile(void)
{
    struct fcb* fcb = find_fcb();
    struct file* f = file_open(&fcb->filename);
    if (f)
    {
        set_current_record(fcb, 0, file_getrecordcount(f));
        set_result(0, true);
    }
    else
        set_result(0xff, false);
}

static void bdos_makefile(void)
{
    struct fcb* fcb = find_fcb();
    struct file* f = file_create(&fcb->filename);
    if (f)
    {
        set_current_record(fcb, 0, 0);
        set_result(0, true);
    }
    else
        set_result(0xff, false);
}

static void bdos_closefile(void)
{
    struct fcb* fcb = find_fcb();
    struct file* f = file_open(&fcb->filename);
    if (file_getrecordcount(f) < 128)
        file_setrecordcount(f, fcb->recordcount);
    int result = file_close(&fcb->filename);
    set_result(result ? 0xff : 0, !result);
}

static void bdos_renamefile(void)
{
    struct fcb* srcfcb = fcb_at(get_xa());
    struct fcb* destfcb = fcb_at(get_xa() + 16);
    int result = file_rename(&srcfcb->filename, &destfcb->filename);
    set_result(result ? 0xff : 0, !result);
}

static void bdos_findnext(void)
{
    struct fcb* fcb = (struct fcb*)&ram[dma];
    memset(fcb, 0, sizeof(struct fcb));
    int i = file_findnext(&fcb->filename);
    set_result(i ? 0xff : 0, !i);
}

static void bdos_findfirst(void)
{
    struct fcb* fcb = find_fcb();
    int i = file_findfirst(&fcb->filename);
    if (i == 0)
        bdos_findnext();
    else
        set_result(i ? 0xff : 0, !i);
}

static void bdos_deletefile(void)
{
    struct fcb* fcb = find_fcb();
    int i = file_delete(&fcb->filename);
    set_result(i ? 0xff : 0, !i);
}

typedef int readwrite_cb(struct file* f, uint8_t* ptr, uint16_t record);

static void bdos_readwritesequential(readwrite_cb* readwrite)
{
    struct fcb* fcb = find_fcb();

    struct file* f = file_open(&fcb->filename);
    int here = get_current_record(fcb);
    int i = readwrite(f, &ram[dma], here);
    set_current_record(fcb, here + 1, file_getrecordcount(f));
    if (i == -1)
        set_result(0xff, false);
    else if (i == 0)
        set_result(1, false);
    else
        set_result(0, true);
}

static void bdos_readwriterandom(readwrite_cb* readwrite)
{
    struct fcb* fcb = find_fcb();

    uint16_t record = fcb->r[0] + (fcb->r[1] << 8);
    struct file* f = file_open(&fcb->filename);
    int i = readwrite(f, &ram[dma], record);
    set_current_record(fcb, record, file_getrecordcount(f));
    if (i == -1)
        set_result(0xff, false);
    else if (i == 0)
        set_result(1, false);
    else
        set_result(0, true);
}

static void bdos_filelength(void)
{
    struct fcb* fcb = find_fcb();
    struct file* f = file_open(&fcb->filename);

    int length = file_getrecordcount(f);
    fcb->r[0] = length;
    fcb->r[1] = length >> 8;
    fcb->r[2] = length >> 16;
}

static void bdos_getsetuser(void)
{
    if (cpu->registers->a == 0xff)
        set_result(0, true);
}

static const char* fill(uint8_t* dest, const char* src, int len)
{
    do
    {
        char c = toupper(*src);
        if (!c || (c == '.'))
            c = ' ';
        else if (c == '*')
            c = '?';
        else
            src++;
        *dest++ = c;
    } while (--len);
    return src;
}

void parse_filename(uint8_t fcb[16], const char* filename)
{
    memset(fcb, 0, 16);
    memset(fcb + 1, ' ', 11);

    {
        const char* colon = strchr(filename, ':');
        if (colon)
        {
            char c = *filename++;
            c = toupper(c);
            if (isalpha(c))
            {
                fcb[0] = c - '@';
                c = *filename++;
            }

            filename = colon + 1;
        }
    }

    /* Read filename part. */

    filename = fill(fcb + 1, filename, 8);
    filename = strchr(filename, '.');
    if (filename)
        fill(fcb + 9, filename + 1, 3);

    set_result(get_xa(), filename);
    cpu->registers->p &= ~0x01;
}

static void bdos_parsefilename(void)
{
    uint8_t* fcb = &ram[dma];
    const char* filename = (const char*)&ram[get_xa()];

    parse_filename(fcb, filename);
}

void bdos_entry(uint8_t bdos_call, bool log)
{
    if (log)
    {
        if (bdos_call < sizeof(bdos_names) / sizeof(*bdos_names))
            fprintf(stderr, "%s", bdos_names[bdos_call]);
        else
            fprintf(stderr, "BDOS_%d", bdos_call);
        fprintf(stderr, "(%04x", get_xa());
        switch (bdos_call)
        {
            case 15:
            case 16:
            case 17:
            case 18:
            case 19:
            case 20:
            case 21:
            case 22:
            case 23:
            case 33:
            case 34:
            case 35:
            case 40:
            {
                struct fcb* fcb = find_fcb();
                fprintf(stderr,
                    " `FCB={'%c:%.11s' CR=%02x R=%02x%02x}",
                    fcb->filename.drive + '@',
                    fcb->filename.bytes,
                    fcb->currentrecord,
                    fcb->r[1],
                    fcb->r[0]);
                break;
            }
        }

        fprintf(stderr, ") -> ");
    }

    cpu->registers->p &= ~0x01;
    switch (bdos_call)
    {
            // clang-format off
		case 0: exit(0); break;
        case 1: bdos_getchar(); break;
        case 2: bdos_putchar(); break;
        case 6: bdos_consoleio(); break;
        case 9: bdos_printstring(); break;
        case 10: bdos_readline(); break;
        case 11: bdos_consolestatus(); break;
        case 12: set_result(0x0022, true); break; // get CP/M version
        case 13: bdos_resetdisk(); break; // reset disk system
        case 14: bdos_selectdisk(); break; // select disk
        case 15: bdos_openfile(); break;
        case 16: bdos_closefile(); break;
        case 17: bdos_findfirst(); break;
        case 18: bdos_findnext(); break;
        case 19: bdos_deletefile(); break;
        case 20: bdos_readwritesequential(file_read); break;
        case 21: bdos_readwritesequential(file_write); break;
        case 22: bdos_makefile(); break;
        case 23: bdos_renamefile(); break;
        case 24: set_result(0xffff, false); break; // get login vector
        case 25: bdos_getdisk(); break; // get current disk
        case 26: dma = get_xa(); break; // set DMA
        case 27: set_result(0, false); break; // get allocation vector
        case 29: set_result(0x0000, false); break; // get read-only vector
        case 31: set_result(0, false); break; // get disk parameter block
        case 32: bdos_getsetuser(); break;
        case 33: bdos_readwriterandom(file_read); break;
        case 34: bdos_readwriterandom(file_write); break;
        case 35: bdos_filelength(); break;
		case 38: set_result(BIOS_ADDRESS, true); break;
        case 40: bdos_readwriterandom(file_write); break;
		case 42: set_result((TPA_BASE>>8) | (himem&0xff00), true); break;
		case 43: bdos_parsefilename(); break;
            // clang-format on

        default:
            showregs();
            fatal("unimplemented bdos entry %d", bdos_call);
    }

    if (log)
    {
        if (cpu->registers->p & 0x01)
            fprintf(stderr, "FAILED ");
        fprintf(stderr, "%04x\n", get_xa());
    }
}
