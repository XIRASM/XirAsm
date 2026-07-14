struct NaturalFrame {
    tag: u8,
    value: u32,
    tail: u16,
}

packed struct PackedFrame {
    tag: u8,
    value: u32,
    tail: u16,
}

packed struct Point {
    x: u16,
    y: u32,
}

packed struct NestedFrame {
    tag: u8,
    point: Point,
    tail: u8,
}

assert(sizeof(NaturalFrame) == 12);
assert(offset_of(NaturalFrame, value) == 4);
assert(offset_of(NaturalFrame, tail) == 8);

assert(sizeof(PackedFrame) == 7);
assert(offset_of(PackedFrame, value) == 1);
assert(offset_of(PackedFrame, tail) == 5);

assert(sizeof(NestedFrame) == 8);
assert(offset_of(NestedFrame, point.y) == 3);

sub rsp, sizeof(NaturalFrame)
mov dword [rsp + offset_of(NaturalFrame, value)], 0x44332211
mov eax, [rsp + offset_of(NaturalFrame, value)]
mov word [rsp + offset_of(NaturalFrame, tail)], 0x6655
add rsp, sizeof(NaturalFrame)

sub rsp, sizeof(PackedFrame)
mov dword [rsp + offset_of(PackedFrame, value)], 0x88776655
mov eax, [rsp + offset_of(PackedFrame, value)]
mov word [rsp + offset_of(PackedFrame, tail)], 0xaa99
add rsp, sizeof(PackedFrame)

sub rsp, sizeof(NestedFrame)
mov dword [rsp + offset_of(NestedFrame, point.y)], 0xddccbbaa
mov eax, [rsp + offset_of(NestedFrame, point.y)]
add rsp, sizeof(NestedFrame)
