x86.use64()

db(0xaa);

region.begin(".text", 0x401000, 4)
    xor eax, eax
    ret

region.begin(".data", 0x402000, 0x10)
    dd(0x44332211);
