/*
 * img2osi
 *
 * Copyright © 2024 Ivo van Poorten
 * BSD-2 License.
 *
 * Input:
 *      - Raw disk image, 40 tracks, 16 sectors per track, 128 bytes per sector
 *        2048 bytes per track, 81920 bytes per disk (80kB)
 *      - Raw disk image, 77 tracks, 24 sectors per track, 128 bytes per sector
 *        3072 bytes per track, 236544 bytes per disk (231kB)
 *      - Raw disk image, 80 tracks, 16 sectors per track, 128 bytes per sector
 *        2048 bytes per track, 163840 bytes per disk (160kB)
 *
 * Output:
 *      OSI Disk Stream format
 *
 *      Track 0: special case, load at $2200, 2048 bytes
 *      All other tracks: OS65D track marker plus 1 sector of either 2048
 *      bytes (8 pages) or 3072 bytes (12 pages).
 *
 * Use case: CP/M-65 port
 *      Always read and write full track to simplify writing sectors and
 *      avoid hard to maintain code to write a 128 byte sector somewhere in
 *      the middle of a track and support different CPU speeds at the same
 *      time. This format also can be copied by OS65D disk copier, and a
 *      custom 128 bytes-per-sector format would not.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "osi.h"

#define toBCD(v) ((v)/10*0x10+(v)%10)       /* only works for inputs 0-99 */

static struct osibitstream oh;

static FILE *inp, *outp;
static uint8_t *trkbuf;
static unsigned int ntracks;
static unsigned int trksize;
static unsigned int delay1;
static unsigned int delay2;
static unsigned int npages;
static int opos;
static uint8_t obit;

static void put_bit(bool bit) {
    if (!obit) {
        obit = 0x80;
        opos++;
    }
    if (bit) {
        trkbuf[opos] |= obit;
    } else {
        trkbuf[opos] &= ~obit;
    }
    obit >>= 1;
}

static void put_byte_8E1(uint8_t byte) {
    bool parity = 0;
    put_bit(0);                 // start bit
    for (int i=0; i<8; i++) {
        bool bit = byte & (1<<i);
        put_bit(bit);
        parity ^= bit;
    }
    put_bit(parity);            // parity
    put_bit(1);                 // stop bit
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "error: usage: img2osi input.img output.os5\n");
        return 1;
    }

    inp = fopen(argv[1], "rb");
    if (!inp) {
        fprintf(stderr, "error: unable to open %s\n", argv[1]);
        return 1;
    }

    fseek(inp, 0, SEEK_END);
    long insize = ftell(inp);
    fseek(inp, 0, SEEK_SET);

    if (insize != 81920 && insize != 236544 && insize != 163840) {
        fprintf(stderr, "error: wrong input file size, expected 81920, "
                        "163840 or 236544 bytes\n");
        return 1;
    }

    outp = fopen(argv[2], "wb");
    if (!outp) {
        fprintf(stderr, "error: unable to open %s\n", argv[2]);
        return 1;
    }

    oh.version = 1;
    oh.offset  = 1;

    if (insize == 81920) {
        ntracks = 40;
        trksize = 0x0d00;
        delay1  = 200;
        delay2  = 32;
        npages  = 8;
        oh.type = TYPE_525_SS;
    } else if (insize == 163840) {
        ntracks = 80;
        trksize = 0x0d00;
        delay1  = 200;
        delay2  = 32;
        npages  = 8;
        oh.type = TYPE_80_SD_SS_300;
    } else {
        ntracks = 77;
        trksize = 0x1500;
        delay1  = 100;
        delay2  = 32;
        npages  = 12;
        oh.type = TYPE_8_SS;
    }

    memcpy(oh.id, "OSIDISKBITSTREAM", 16);
    fwrite(&oh, sizeof(oh), 1, outp);
    for (int i=0; i<256-sizeof(oh); i++)        // pad header with 0xff
        fputc(0xff, outp);


    trkbuf = malloc(trksize);
    if (!trkbuf) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }

    for (int i=0; i<ntracks; i++) {
        memset(trkbuf, 0xff, trksize);

        opos = 0;
        obit = 0x80;

        if (!i) {                           // track 0
            for (int j=0; j<delay1*8; j++)
                put_bit(1);

            put_byte_8E1(0x22);             // MSB load address
            put_byte_8E1(0x00);             // LSB load address
            put_byte_8E1(0x08);             // size in pages

            for (int j=0; j<2048; j++)
                put_byte_8E1(fgetc(inp));
            if (npages > 8)
                fseek(inp, (npages-8) * 256, SEEK_CUR);

        } else {                            // track 1...ntracks
            for (int j=0; j<delay1*8; j++)
                put_bit(1);

            put_byte_8E1(0x43);             // track
            put_byte_8E1(0x57);             // markers
            put_byte_8E1(toBCD(i));         // track number in BCD
            put_byte_8E1(0x58);             // end

            for (int j=0; j<delay2*8; j++)
                put_bit(1);

            put_byte_8E1(0x76);             // sector marker
            put_byte_8E1(0x01);             // sector number
            put_byte_8E1(npages);           // sector size in pages

            for (int j=0; j<npages*256; j++)
                put_byte_8E1(fgetc(inp));

            put_byte_8E1(0x47);             // end
            put_byte_8E1(0x53);             // markers
        }

        while (opos < trksize)
            put_bit(1);

        if (fwrite(trkbuf, trksize, 1, outp) != 1) {
            fprintf(stderr, "error: writing to %s\n", argv[2]);
            return 1;
        }
    }

    fclose(inp);
    fclose(outp);
}
