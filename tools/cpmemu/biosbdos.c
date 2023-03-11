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
#include "globals.h"

#define LOAD_ADDRESS 0x0200
#define ZP_ADDRESS 0x00
#define BDOS_ADDRESS 0xff00
#define BIOS_ADDRESS 0xff01
#define EXIT_ADDRESS 0xff02

static uint16_t dma;
static uint8_t current_disk;
static int exitcode = 0;

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

static uint16_t get_xa(void)
{
    return (cpu->registers->x << 8) | cpu->registers->y;
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

static int bdos_cb(M6502* mpu, uint16_t address, uint8_t data)
{
    bdos_entry(cpu->registers->y);
    return 0;
}

static int bios_cb(M6502* mpu, uint16_t address, uint8_t data)
{
    bios_entry(cpu->registers->y);
    return 0;
}

static int exit_cb(M6502* mpu, uint16_t address, uint8_t data)
{
    exit(0);
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
    uint16_t address = LOAD_ADDRESS;
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
    relotable = do_relocation(relotable, ZP_ADDRESS);
    do_relocation(relotable, LOAD_ADDRESS >> 8);
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

        cpu->callbacks->call[BDOS_ADDRESS] = bdos_cb;
        cpu->callbacks->call[BIOS_ADDRESS] = bios_cb;
        cpu->callbacks->call[EXIT_ADDRESS] = exit_cb;

        /* Push the return address onto the stack. */
        ram[0x01fe] = EXIT_ADDRESS & 0xff;
        ram[0x01ff] = EXIT_ADDRESS >> 8;
        cpu->registers->s = 0xfd;

        int fd = open(user_command_line[0], O_RDONLY);
        if (fd == -1)
            fatal("couldn't open program: %s", strerror(errno));
        read(fd, &ram[LOAD_ADDRESS], BDOS_ADDRESS - LOAD_ADDRESS);
        close(fd);

        uint16_t relotable =
            (ram[LOAD_ADDRESS + 2] | (ram[LOAD_ADDRESS + 3] << 8)) +
            LOAD_ADDRESS;
        relocate(relotable);

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

        ram[LOAD_ADDRESS + 5] = BDOS_ADDRESS & 0xff;
        ram[LOAD_ADDRESS + 6] = BDOS_ADDRESS >> 8;
        cpu->registers->pc = LOAD_ADDRESS + 7;
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
        case 0:
            bios_coldboot();
            return;
        case 1:
            bios_warmboot();
            return;
        case 2:
            bios_const();
            return; // const
        case 3:
            bios_getchar();
            return; // conin
        case 4:
            bios_putchar();
            return; // conout
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
    uint8_t c = cpu->registers->x;
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
        if (c == '$')
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
        set_result(1, true);
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
        set_result(1, true);
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

void bdos_entry(uint8_t bdos_call)
{
    switch (bdos_call)
    {
            // clang-format off
        case 1: bdos_getchar(); return;
        case 2: bdos_putchar(); return;
        case 6: bdos_consoleio(); return;
        case 9: bdos_printstring(); return;
        case 10: bdos_readline(); return;
        case 11: bdos_consolestatus(); return;
        case 12: set_result(0x0022, true); return; // get CP/M version
        case 13: bdos_resetdisk(); return; // reset disk system
        case 14: bdos_selectdisk(); return; // select disk
        case 15: bdos_openfile(); return;
        case 16: bdos_closefile(); return;
        case 17: bdos_findfirst(); return;
        case 18: bdos_findnext(); return;
        case 19: bdos_deletefile(); return;
        case 20: bdos_readwritesequential(file_read); return;
        case 21: bdos_readwritesequential(file_write); return;
        case 22: bdos_makefile(); return;
        case 23: bdos_renamefile(); return;
        case 24: set_result(0xffff, false); return; // get login vector
        case 25: bdos_getdisk(); return; // get current disk
        case 26: dma = get_xa(); return; // set DMA
        case 27: set_result(0, false); return; // get allocation vector
        case 29: set_result(0x0000, false); return; // get read-only vector
        case 31: set_result(0, false); return; // get disk parameter block
        case 32: bdos_getsetuser(); return;
        case 33: bdos_readwriterandom(file_read); return;
        case 34: bdos_readwriterandom(file_write); return;
        case 35: bdos_filelength(); return;
		case 38: set_result(BIOS_ADDRESS, true); return;
        case 40: bdos_readwriterandom(file_write); return;
            // clang-format on
    }

    showregs();
    fatal("unimplemented bdos entry %d", bdos_call);
}
