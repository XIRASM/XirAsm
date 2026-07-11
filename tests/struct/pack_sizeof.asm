packed struct Header {
    magic: u16 = 0x4241,
    tail: u16,
}

packed struct SaveArea {
    rax: u64,
    rcx: u64,
}

const hdr: Header = Header { tail: 0x4443 }
const packed_hdr: bytes = pack(hdr)
assert(pack(hdr) == b"ABCD");
emit.u8(lengthof(pack(hdr)));
emit.bytes(packed_hdr);
sub rsp, sizeof(SaveArea)
