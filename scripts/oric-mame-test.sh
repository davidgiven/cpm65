#!/bin/sh
set -e

diskimage=/tmp/$$.$4
trap "rm -f $diskimage" EXIT
cp $2 $diskimage
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy chronic mame $1 -ext microdisc -flop $diskimage -video none -autoboot_script $3 -nothrottle -nosleep -snapshot_directory snap -sound none -rompath roms || \
    ( \
        echo "Failed!" && \
        echo "Run this to debug:" && \
        echo "mame $1 -ext microdisc -flop $2 -autoboot_script $3 -nothrottle -nosleep -snapshot_directory snap -rompath roms" &&
        false \
    )

