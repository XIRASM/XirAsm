packed struct Pair {
    lo: u8 = 1,
    hi: u8 = 2,
}

emit.bytes(pack(Pair { lo: 3, hi: 4 }));
emit.u8(lengthof(pack(Pair { lo: 5, hi: 6 })));
