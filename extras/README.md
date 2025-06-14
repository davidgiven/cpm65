Making blank D2M images seems to be pretty hard --- VICE can do it through the
GUI, but c1541 can't (even though c1541 is part of VICE? I think?).
`empty.d2m.gz` is a compressed blank image containing an empty CBMFS filesystem
which has been hand edited to also an empty CPMFS filesystem. It's not a true
combifs like the D64 images.