#!/bin/sh
set -e

get_rom() {
    rom=$2
    if [ "$rom" = "" ]; then
        rom=$(basename $1)
    fi
    if ! [ -f roms/$rom ]; then
        mkdir -p roms
        wget -O roms/$rom $1
    fi
}

URL='https://archive.org/download/MAME217RomsOnlyMerged/MAME%200.217%20ROMs%20%28merged%29.zip'
get_rom $URL/a800xl.zip
get_rom $URL/bbcm.zip
get_rom $URL/saa5050.zip
get_rom $URL/apple2e.zip
get_rom $URL/a2diskiing.zip
get_rom $URL/d2fdc.zip
get_rom $URL/votrax.zip votrsc01a.zip
get_rom $URL/oric1.zip
get_rom $URL/oric_microdisc.zip
