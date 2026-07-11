emit.u8(0x42);

fn emit_from_import(value: u64) {
    emit.u8(value);
    emit.u8(value + 1);
}
