packed struct Point {
    x: u16,
    y: u16,
}

union ValueBits {
    raw: u32,
    bytes: Point,
}

packed struct WinLike {
    tag: u16,
    value: ValueBits,
    tail: u8,
}

struct NaturalBox {
    tag: u8,
    value: ValueBits,
    tail: u8,
}

packed struct ThreeBytes {
    a: u8,
    b: u16,
}

union NaturalOdd {
    three: ThreeBytes,
    word: u16,
}

packed union PackedOdd {
    three: ThreeBytes,
    word: u16,
}
