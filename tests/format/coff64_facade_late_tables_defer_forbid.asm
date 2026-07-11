import("../../include/format/coff64.inc");

coff64_obj(1, 1);

virtual.begin(0);
scratch:
emit.u8(0xaa);
virtual.end();

defer {
    emit.bytes(load.bytes(scratch, 1));
}

