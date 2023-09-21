#include <cpm.h>
#include <stdlib.h>
#include <stdbool.h>

static uint8_t *CHBAS  = (uint8_t *) 0x02f4;

/* FILDAT is normally used by screen drawing routines in graphics modes.
 * It is unused now, so we use it to signal whether memory for a font
 * has been reserved.
 */

static uint8_t *FILDAT = (uint8_t *) 0x02fd;

static uint8_t mem_base;
static uint8_t mem_end;
static uint16_t tpa;
static _Bool warmboot = false;

void main() {
    if (!*FILDAT) {                                     // first run
        tpa = cpm_bios_gettpa();
        mem_base = tpa & 0xff;
        mem_end = tpa >> 8;

        if (mem_end <= 0xc0) {                      // font in high memory
            mem_end = (mem_end & ~3) - 4;           // 1kB aligned
            cpm_bios_settpa(mem_base, mem_end);
            *FILDAT = mem_end;
            warmboot = true;
        } else {                                    // font in low memory
            if (mem_base & 3)
                mem_base = (mem_base & ~3) + 8;     // 1kB aligned
            else
                mem_base += 4;
            cpm_bios_settpa(mem_base, mem_end);
            *FILDAT = mem_base-4;

            cpm_printstring("first run, reserving low memory\r\n"
                            "run again to change font\r\n");

            return;
        }
    } 

    if (cpm_fcb.f[0] == ' ') {
        cpm_printstring("specify font file\r\n");
        goto errout;
    }

    if (cpm_fcb.f[8] == ' ' && cpm_fcb.f[9] == ' ' && cpm_fcb.f[10] == ' ') {
        cpm_fcb.f[8]  = 'F';
        cpm_fcb.f[9]  = 'N';
        cpm_fcb.f[10] = 'T';
    }

    cpm_fcb.ex = 0;
    cpm_fcb.cr = 0;
    if (cpm_open_file(&cpm_fcb)) {
        cpm_printstring("file not found\r\n");
        goto errout;
    }

    for (int i=0; i<8; i++) {
        cpm_set_dma((uint8_t *)(*FILDAT<<8) + i*128);
        cpm_read_sequential(&cpm_fcb);
    }
    cpm_close_file(&cpm_fcb);

    *CHBAS = *FILDAT;                       // set font

errout:
    if (warmboot) {
        cpm_get_set_user(0);                // assure we can read CCP.SYS
        cpm_warmboot();
    }
}
