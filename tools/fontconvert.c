/* Amstrad NC200 cpmish BIOS © 2019 David Given
 * This file is distributable under the terms of the 2-clause BSD license.
 * See COPYING.cpmish in the distribution root directory for more information.
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include "libbdf.h"
#define LINEHEIGHT 8

static void fatal(const char* msg, ...)
{
    va_list ap;
    va_start(ap, msg);

    fprintf(stderr, "error: ");
    vfprintf(stderr, msg, ap);
    fprintf(stderr, "\n");

    exit(1);
}

int main(int argc, const char* argv[])
{
    if (argc != 2)
        fatal("fontconvert <inputfile>");

    BDF* bdf = bdf_load(argv[1]);
    if (bdf->height != LINEHEIGHT)
        fatal("font is not 4x8");

    for (int c = 32; c < 127; c++)
    {
        Glyph* glyph = bdf->glyphs[c];

        /* The glyph data is a 8-element array of bytes. Each byte contains
         * one scanline, with the glyph data repeated in both nibbles. */

        const uint8_t* p = glyph->data;

        printf(
            "\t.byte 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x, "
            "0x%02x ; char %d\n",
            p[0] | (p[0]>>4),
            p[1] | (p[1]>>4),
            p[2] | (p[2]>>4),
            p[3] | (p[3]>>4),
            p[4] | (p[4]>>4),
            p[5] | (p[5]>>4),
            p[6] | (p[6]>>4),
            p[7] | (p[7]>>4),
            c);
    }

    return 0;
}

// vim: ts=4 sw=4 et
