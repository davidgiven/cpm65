#include "cpm.h"
#include <stdlib.h>

static uint8_t *RAMSIZ = (uint8_t *) 0x02e4;
static uint8_t *CHBAS  = (uint8_t *) 0x02f4;

static uint8_t memtop;
static uint8_t mem_end;
static uint16_t tpa;
static _Bool first_time;

int main() {
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

    memtop = *RAMSIZ;
    tpa = cpm_bios_gettpa();
    mem_end = (tpa >> 8);

    first_time = memtop == mem_end;
    if (first_time)
        mem_end -= 4;

    cpm_bios_settpa(tpa & 0xff, mem_end);   // reserve memory

    for (int i=0; i<8; i++) {
        cpm_set_dma((uint8_t *)(mem_end<<8) + i*128);
        cpm_read_sequential(&cpm_fcb);
    }
    cpm_close_file(&cpm_fcb);

    *CHBAS = mem_end;       // set font

    if (first_time) {
        cpm_get_set_user(0);     // assure we can read CCP.SYS
        cpm_warmboot();
    }

    return 0;

errout:
    return 1;
}
