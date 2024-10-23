#!/usr/bin/env python3

# Parser for Intel HEX format, intentionally lenient

# This can parse .hex files from the Nintendo leaks, since they use a variant of the format
# with a 3-byte payload in the extended segment address records (most other tools reject this).

# Usage: ./hex2bin_fixed.py input.hex > out.bin
# (ie. hex file from stdin (or filename arg), data to stdout)
# If you're using PowerShell... don't; it seems to re-encode the data into UTF-16, breaking it. >.>


# modified by MrL314 Sep 3, 2021 for more functionality

import binascii, argparse, os, sys

def checksum_of(data):
    # Sum of byte values
    chk = 0
    for b in data:
        chk = (chk + b) & 0xff

    # Checksum is two's complement of sum
    return (~chk + 1) & 0xff

def parse_record(lineno, line):
    if not line.startswith(":"):
        return None

    bs = binascii.unhexlify(line[1:])

    count = bs[0]
    addr = bs[1] << 8 | bs[2]
    rtype = bs[3]
    payload = bs[4:-1]
    checksum = bs[-1]

    if len(payload) != count:
        print("error: invalid payload length on line {} (expected {:02X} bytes, got {:02X})".format(lineno, count, len(payload)), file=sys.stderr)
    
    actual_checksum = checksum_of(bs[:-1])
    if actual_checksum != checksum:
        print("error: invalid checksum on line {} (expected {:02X}, got {:02X})".format(lineno, checksum, actual_checksum), file=sys.stderr)
        sys.exit(1)

    return (rtype, addr, payload)

#data = bytearray()
#offset = 0


def hex2bin_file(filename, data=bytearray(), fill_byte=0):
    offset = 0

    lineno = 1

    file_lines = []
    with open(filename, "r") as f:
        for line in f:
            file_lines.append(line.replace("\n", ""))


    for line in file_lines:
        
        # Skip lines that don't start with a :
        if not line.startswith(":"):
            continue

        rtype, addr, payload = parse_record(lineno, line.strip())
        addr = addr & 0x7FFFFF
        offset = offset & 0x7FFFFF
        if rtype == 0:
            # Data literal, just write to buffer
            start_addr = offset + addr
            end_addr = offset + addr + len(payload)
            
            # Extend byte array so the data fits
            if len(data) < end_addr:
                new_size = end_addr - len(data)
                data.extend(bytearray([fill_byte for _ in range(new_size)]))
                #data[start_addr:] = [fill_byte for _ in range(new_size)]
            
            # Fill array
            data[start_addr:end_addr] = payload
        elif rtype == 1:
            # End of file
            break
        elif rtype == 2:
            # Extended segment address, set offset for future data
            # NOTE: File format specifies this must be 2 bytes,
            # but Nintendo seems to use a format with 3 bytes... >.>
            offset = int.from_bytes(payload, byteorder="big", signed=False) * 16
        else:
            # We don't support Start Segment Address (03), 
            # Extended Linear Address (04) or Start Linear Address (05)
            # those seem to be x86-specific anyway, so meh
            print("error: unsupported record type {:02X}".format(rtype), file=sys.stderr)
            sys.exit(1)

        lineno += 1
    else:
        # We ran out of lines before hitting an end of file record (which would break)
        print("error: hit end of input before EOF record", file=sys.stderr)
        sys.exit(1)

    return data






def include_file(filename, data=bytearray(), fill_byte=0):


    #print(data[0x8000:0x8020])



    with open(filename, "r", encoding="utf-8") as file:

        for line in file:
            if line.lstrip().rstrip() != "":
                L = line.replace("\n", "").split()

                L = [L[0], L[1], "".join(L[2:])]

                #print(L)

                sp = filename.replace("\\", "/").split("/")
                path = "/".join(sp[:-1])

                if path != "": path += "/"


                d = []
                with open(path + L[0], "rb") as sf:
                    d = sf.read()

                f_off, o_off, sz = L[2].split(",")

                f_start = int(f_off, 16)
                size = min(int(sz, 16), len(d) - f_start)
                start_addr = int(o_off, 16)
                end_addr = start_addr + size


                if len(data) < end_addr:
                    new_size = end_addr - len(data)
                    data.extend(bytearray([fill_byte for _ in range(new_size)]))

               
                    
                data[start_addr:end_addr] = d[f_start:f_start+size]

    #print(data[0x5fa000:0x5fa020])

    return data



def format_rom(frmt, data, fill_byte=0):
    
    if frmt == "16":

        end = len(data)
        empt = 0x1000000#(((end//0x100000)+1)*0x100000) - end
        data.extend(bytearray(empt-end))
        data[end:] = [fill_byte for _ in range(empt-end)]

        out_data = bytearray()#bytearray([fill_byte for _ in range(0x1000000)])

        
        for i in range(0x18):
            A = i * 0x10000
            BASE_ADDR = A + 0x8000

            #print("BASE_ADDR: ", format(BASE_ADDR, "06x"))

            out_data.extend(data[BASE_ADDR:BASE_ADDR+0x8000])


        for i in range(0x28):
            BASE_ADDR = 0x4C0000 + i * 0x8000

            #print("BASE_ADDR: ", format(BASE_ADDR, "06x"))
            
            out_data.extend(data[BASE_ADDR:BASE_ADDR+0x8000])
        
        data = out_data#[:0x200000]
    
    elif frmt == "4,4,4,4":
        raise Exception("Format currently unsupported as of right now: " + frmt)


    elif frmt == "4":
        end = len(data)
        empt = 0x1000000#(((end//0x100000)+1)*0x100000) - end
        data.extend(bytearray(empt-end))
        data[end:] = [fill_byte for _ in range(empt-end)]

        out_data = bytearray()#bytearray([fill_byte for _ in range(0x1000000)])

        
        for i in range(0x10):
            A = i * 0x8000
            BASE_ADDR = A

            out_data.extend(data[BASE_ADDR:BASE_ADDR+0x8000])
        
        data = out_data#[:0x200000]


    return data






if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Convert an Intex-Hex file into a binary file.")

    #parser.add_argument("file", metavar="file", type=str, help="Name of file to assemble")

    parser.add_argument("-o", dest="outputname", type=str, help="Output file name.")

    parser.add_argument("-m", dest="m_var", type=str, help="m flag?")

    parser.add_argument("-c", dest="fill_char", type=str, help="Byte to fill unused space with")

    parser.add_argument("-i", dest="include_files", type=str, nargs="*", action="append", default=[], help="File that holds include instructions")

    parser.add_argument("-r", dest="rom_format", type=str, help="Rom Format")    

    parser.add_argument("-f", dest="hex_files", type=str, nargs="*", action="append", default=[], help="Hex files to use")    

    #parser.add_argument("-i", dest="WARG", action="store_true", help="unknown as of this time")


    FILL_BYTE = None

    HEX_FILES = []

    INC_FILES = []

    ROM_FORMAT = ""




    KNOWN_ARGS, EXTRA_ARGS = parser.parse_known_args()


    ARGS = vars(KNOWN_ARGS)

    
    #print(KNOWN_ARGS)




    data = bytearray()

    if "fill_char" in ARGS:
        FILL_BYTE = ARGS["fill_char"]

    if FILL_BYTE == None: FILL_BYTE = "00"

    FILL_VAL = int(FILL_BYTE, 16)

    #print(FILL_VAL)
    #print(FILL_VAL)


    HEX_FILES = ARGS["hex_files"]
    ind = 0
    while ind < len(HEX_FILES):
        h = HEX_FILES[ind]

        if type(h) == type(list()):
            HEX_FILES = HEX_FILES[:ind] + h + HEX_FILES[ind+1:]
            continue

        ind += 1


    INC_FILES = ARGS["include_files"]
    ind = 0
    while ind < len(INC_FILES):
        h = INC_FILES[ind]

        if type(h) == type(list()):
            INC_FILES = INC_FILES[:ind] + h + INC_FILES[ind+1:]
            continue

        ind += 1

    if "rom_format" in ARGS:
        ROM_FORMAT = ARGS["rom_format"]

    #print(HEX_FILES)

    for f in HEX_FILES:
        data = hex2bin_file(f, data=data, fill_byte=FILL_VAL)



    #data = format_rom(ROM_FORMAT, data, fill_byte=FILL_VAL)

    for f in INC_FILES:
        data = include_file(f, data=data, fill_byte=FILL_VAL)

    #print(data[0x5fa000:0x5fa020])

    

    data = format_rom(ROM_FORMAT, data, fill_byte=FILL_VAL)




    with open(ARGS["outputname"], "wb") as f:
        f.write(bytes(data))





    # Print output data to stdout
    #sys.stdout.buffer.write(bytes(data))
    #sys.stdout.buffer.flush()
    #with open(fileinput.filename() + ".bin", "wb") as file:
    #    file.write(bytes(data))
    # :)
    sys.exit(0)