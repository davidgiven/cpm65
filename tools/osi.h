#pragma once
#include <stdint.h>

struct osibitstream {
    uint8_t id[16];
    uint8_t version;
    uint8_t type;
    uint8_t offset;
};

enum osi_disk_type {
    TYPE_525_SS,
    TYPE_8_SS
};
