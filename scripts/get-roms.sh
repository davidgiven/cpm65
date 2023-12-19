#!/bin/sh
set -e

get_rom() {
    rom=$2
    if [ "$rom" = "" ]; then
        rom=$(basename $1)
    fi
    if ! [ -f roms/$rom ]; then
        mkdir -p roms
        wget -q -O roms/$rom $1
    fi
}

URL='https://archive.org/download/MAME217RomsOnlyMerged/MAME%200.217%20ROMs%20%28merged%29.zip'

get_rom $URL/a2diskiing.zip
get_rom $URL/a800xl.zip
get_rom $URL/apple2e.zip
get_rom $URL/bbcm.zip
get_rom $URL/c1541.zip
get_rom $URL/c64.zip
get_rom $URL/d2fdc.zip
get_rom $URL/oric1.zip
get_rom $URL/oric_microdisc.zip
get_rom $URL/saa5050.zip
get_rom $URL/vic1001.zip
get_rom $URL/pet4016.zip
get_rom $URL/pet4032b.zip
get_rom $URL/pet8032.zip
get_rom $URL/c8050.zip
get_rom $URL/c8050fdc.zip
get_rom $URL/c4040.zip
get_rom $URL/c2040_fdc.zip
get_rom $URL/vic20_fe3.zip vic20.zip
get_rom $URL/votrax.zip votrsc01a.zip