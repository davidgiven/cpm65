/* sys © 2024 Eduardo Casino
 * This program is distributable under the terms of the 2-clause BSD license.
 * See COPYING.cpmish in the distribution root directory for more information.
 * 
 * System transfer utility. Transfer reserved sectors and system files to a 
 * newly formatted disk, making it bootable.
 * 
 * copy_file() code taken and adapted from the copy utility.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <cpm.h>

#define SYSTEM_FILES 2
const char sys_files[SYSTEM_FILES][11] = {
    "CCP     SYS",
    "BDOS    SYS"
};

DPH* dph;
DPB* dpb;
FCB src_fcb;
FCB dst_fcb;
uint8_t src_drive;
uint8_t dst_drive;
uint16_t src_reserved;
uint16_t dst_reserved;
uint8_t *buffer;
uint8_t *top_mem;
uint16_t buffer_size;

static void print_error(const char* msg)
{
    cpm_printstring("Error: ");
    cpm_printstring(msg);
}

static void cr(void)
{
    cpm_printstring("\n\r");
}

static void usage(void)
{
    cpm_printstring("Syntax: sys [<src drive>] <dst drive>\n\r");
    cpm_warmboot();
}

static void fatal(const char* msg)
{
    print_error(msg);
    cr();
    cpm_warmboot();
}

static void fatal_drv(const char *msg, uint8_t dr)
{
    print_error(msg);
    cpm_conout('A' + dr);
    cpm_printstring("'.\n\r");
    cpm_warmboot();
}    

uint16_t get_reserved_sectors(uint8_t dr)
{
    dph = cpm_bios_seldsk(dr);
    if (!dph)
        fatal_drv("Invalid drive '", dr);
    dpb = (DPB*)dph->dpb;
    return dpb->off;
}

void media_change(const char *desc, uint8_t dr)
{
    cpm_printstring("\n\rInsert ");
    cpm_printstring(desc);
    cpm_printstring(" disc into drive '");
    cpm_conout('A' + dr);
    cpm_printstring("' and press any key...");
    cpm_bios_conin();
    cr();
}

void copy_reserved_sectors(void)
{
    uint32_t sector = 0;
    uint8_t *dma;
    uint16_t s;

    while ((uint16_t)sector < src_reserved)
    {
        /* Fill the buffer */

        cpm_select_drive(src_drive);
        dma = buffer;
        s = 0;

        while (((uint16_t)(sector+s) < src_reserved) && ((uint16_t)dma < (uint16_t)top_mem))
        {
            cpm_conout('r');
            cpm_bios_setdma(dma);
            uint32_t read_sec = sector+s;
            cpm_bios_setsec(&read_sec);
            if (cpm_bios_read())
                fatal_drv("Reading from drive '", src_drive);

            dma += 128;
            ++s;
        }

        /* Transfer to destination */

        if ( src_drive == dst_drive )
            media_change("destination", dst_drive);

        cpm_select_drive(dst_drive);
        dma = buffer;
        s = 0;
    
        while (((uint16_t)(sector+s) < src_reserved) && ((uint16_t)dma < (uint16_t)top_mem))
        {
            cpm_conout('w');
            cpm_bios_setdma(dma);
            uint32_t write_sec = sector+s;
            cpm_bios_setsec(&write_sec);
            if (cpm_bios_write(0))
            {
                fatal_drv("Writing to drive '", dst_drive);
            }

            dma += 128;
            ++s;
        }

        if ( src_drive == dst_drive )
            media_change("source", src_drive);

        sector += s;
    }
    
    cpm_select_drive(src_drive);

    cr();
}

static void print_filename(FCB* f)
{
    cpm_conout(('A' - 1) + f->dr);
    cpm_conout(':');

    for (uint8_t i = 0; i < 11; i++)
    {
        uint8_t b = f->f[i] & 0x7f;
        if (b != ' ')
        {
            if (i == 8)
                cpm_conout('.');
            cpm_conout(b);
        }
    }
}

static void copy_file(void)
{
    bool dst_open = false;

    print_filename(&src_fcb);

    src_fcb.ex = 0;
    src_fcb.cr = 0;
    if (cpm_open_file(&src_fcb))
    {
        cpm_printstring(" - Not found.\n\r");
        return;
    }
    cr();

    uint8_t i = false;
    do
    {
        uint16_t sr = 0;
        while (sr != buffer_size)
        {
            cpm_set_dma(buffer + sr*128);
            i = cpm_read_sequential(&src_fcb);

            if (i != 0)
            {
                if (CPME_NOBLOCK == cpm_errno)
                    break;
                else
                    fatal("Cannot read from source file.");
            }

            cpm_conout('r');

            sr++;
        }

        if ( src_drive == dst_drive )
            media_change("destination", dst_drive);

        if (!dst_open)
        {
            ++dst_open;
            
            dst_fcb.ex = 0;
            dst_fcb.cr = 0;
            dst_fcb.f[8] &= ~0x80;              /* Remove read-only attribute */
            cpm_set_file_attributes(&dst_fcb);
            cpm_delete_file(&dst_fcb);
            dst_fcb.ex = 0;
            dst_fcb.cr = 0;
            if (cpm_make_file(&dst_fcb))
                fatal("Cannot create destination file.");
        }

        uint16_t dr = 0;
        while (dr != sr)
        {
            cpm_conout('w');
            cpm_set_dma(buffer + dr*128);
            if (cpm_write_sequential(&dst_fcb))
            {
                if (CPME_DISKFULL == cpm_errno)
                    fatal("Disk full.");
                else
                    fatal("Cannot write to destination file.");
            }
            dr++;
        }

        if ( src_drive == dst_drive )
            media_change("source", src_drive);
    }
    while (i == 0);

    cpm_close_file(&dst_fcb);
    dst_fcb.f[8] |= 0x80;                       /* Set read-only and system attributes */
    dst_fcb.f[9] |= 0x80;
    cpm_set_file_attributes(&dst_fcb);

    cr();
}

void copy_system_files(void)
{
    cpm_printstring("Copying system files:\n\r");

    buffer_size = ((uint16_t)top_mem - (uint16_t)buffer) / 128;

    for (int f=0; f < SYSTEM_FILES; ++f)
    {
        for (int i=0; i < 11; ++i)
            src_fcb.f[i] = sys_files[f][i];
        dst_fcb = src_fcb;
        src_fcb.dr = src_drive+1;
        dst_fcb.dr = dst_drive+1;

        copy_file();
    }
}

int main()
{
    if (cpm_fcb.dr == 0 || cpm_fcb.f[0] != ' ' || cpm_fcb2.f[0] != ' ')
        usage();

    if (cpm_fcb2.dr != 0)
    {
        src_drive = cpm_fcb.dr-1;
        dst_drive = cpm_fcb2.dr-1;
    }
    else
    {
        src_drive = cpm_get_current_drive();
        dst_drive = cpm_fcb.dr-1;
    }
    
    src_reserved = get_reserved_sectors(src_drive);
    dst_reserved = get_reserved_sectors(dst_drive);

    /* Page-aligned buffer start and end */
    top_mem = (uint8_t *)(cpm_gettpa() & 0xff00);
    buffer = (uint8_t *)(((uint16_t)cpm_ram+255) & 0xff00);

    uint16_t mem_size = top_mem - buffer;

    if (mem_size < 128)
        fatal("Not enough ram.");
    
    if (!src_reserved)
    {
        cpm_printstring("No reserved sectors.\n\r");
    }
    else
    {
        if (src_reserved != dst_reserved)
            fatal_drv("Different number of reserved sectors on drive '", dst_drive);

        cpm_printstring("Transferring boot sectors:\n\r");

        copy_reserved_sectors();
    }

    copy_system_files();

    cpm_printstring("Done.\n\r");

    return 0;
}
