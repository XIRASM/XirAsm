fn emit_pair(value: u64) {
    emit.u8(value);
    emit.u8(value + 1);
}

const value = 1
emit_pair(2);
{
    let value = 2
    emit.u8(value);
}
emit.u8(value);
