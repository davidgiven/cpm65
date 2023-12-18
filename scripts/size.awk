/ [0-9]+/ {
    size[$2] = ("0x"$3)+0
}

END {
    print(size[".text"] + size[".data"] + size[".bss"])
}
