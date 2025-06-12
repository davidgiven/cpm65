rw_*: read/write layer, i.e. read_sector and write_sector.

io_*: protocol layer, which does the work.

In addition there's some common stuff, like io_ieee488.S which contains a
platform-independent IEE488 layer on top of PET/C64/Vic20 etc.


The *yload* files contain a fastloader which is extremely heavily based on
MagerValp's uload3, which is BSD licensed; see
https://www.lemon64.com/forum/viewtopic.php?t=80458. However, I have rewritten
and modified basically every line of it so that calling it derived from uload3
is probably an insult to uload3. 
