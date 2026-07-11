region.begin("data", 0x1000, 0)

start:
emit.u8(0x11)

assert(region_file_size(start) == 1)
