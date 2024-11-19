#pragma once
#include <stdint.h>

struct osibitstream {
    char id[16];
    uint8_t version;
    uint8_t type;
    uint8_t offset;
};

enum osi_disk_type {
    TYPE_525_SS = 0,
    TYPE_8_SS   = 1,
    TYPE_40_SD_SS_300 = 0,          // identical to TYPE_525_SS
    TYPE_77_DD_SS_360 = 1,          // identical to TYPE_8_SS
    TYPE_80_SD_SS_300 = 2
};
