fn patch_u32(addr: u64, value: u64) {
    defer {
        store.u32(addr, value);
    }
}

fn patch_blob(addr: u64, blob: bytes) {
    defer {
        store.bytes(addr, blob);
        assert(bytes.eq(load.bytes(addr, lengthof(blob)), blob));
    }
}

fn check_text(text: string) {
    defer {
        assert(text == "quote "" slash \ ok");
    }
}

region.begin(".flat", 0, 0);
header:
dd(0);
blob:
reserve(5);
body:
db(1, 2, 3);
end:

patch_u32(header, end - body);
const bytes_with_control: bytes = bytes.from_hex("00410a225c")
const text_with_quote: string = "quote "" slash \ ok"
patch_blob(blob, bytes_with_control);
check_text(text_with_quote);

defer {
    assert(load.u32(header) == 3);
    assert(bytes.eq(load.bytes(blob, 5), bytes_with_control));
}
