struct NaturalHeader {
    tag: u8 = 0x41
    size: u32 = 0x11223344
}

packed struct PackedHeader {
    tag: u8 = 0x42
    tail: u16
}

packed struct Point {
    x: u16
    y: u16
}

union ValueBits {
    raw: u32
    point: Point
}

packed struct Record {
    kind: u8
    value: ValueBits
}

packed struct ThreeBytes {
    tag: u8
    value: u16
}

union NaturalOdd {
    bytes: ThreeBytes
    word: u16
}

packed union PackedOdd {
    bytes: ThreeBytes
    word: u16
}

packed struct SignedValues {
    byte: i8
    word: i16
    dword: i32
    qword: i64
}

const natural: NaturalHeader = NaturalHeader { }
emit.struct(natural)
emit.u8(sizeof(NaturalHeader))
emit.u8(offset_of(NaturalHeader, size))
emit.u32(natural.size)

emit.bytes(pack(PackedHeader { tail: 0x4443 }))

const record: Record = Record {
    kind: 1,
    value: ValueBits {
        point: Point {
            x: 0x1122,
            y: 0x3344
        }
    }
}

emit.bytes(pack(record))

const odd: PackedOdd = PackedOdd {
    bytes: ThreeBytes {
        tag: 0x55,
        value: 0x7766
    }
}

emit.bytes(pack(odd))
emit.u8(sizeof(NaturalOdd))
emit.u8(sizeof(PackedOdd))
emit.u8(record.kind)

emit.struct(SignedValues {
    byte: -1,
    word: -2,
    dword: -3,
    qword: -4
})
