import("../../include/format/format.inc");

region.begin("macho", 0, 0);
header:
macho_header64_arm64(macho_mh_object, 0, 0, 0);

defer {
    assert(load.u32(header) == macho_magic_64);
    assert(load.u32(header + 4) == macho_cpu_type_arm64);
    assert(load.u32(header + 12) == macho_mh_object);
}
