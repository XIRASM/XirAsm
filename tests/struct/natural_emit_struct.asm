struct NaturalHeader {
    tag: u8 = 0x41
    size: u32 = 0x11223344
}

let hdr: NaturalHeader = NaturalHeader { }
emit.struct(hdr);
emit.u8(sizeof(NaturalHeader));
emit.u8(offset_of(NaturalHeader, size));
emit.u32(hdr.size);
