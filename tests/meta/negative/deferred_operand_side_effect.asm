let saved: list = list.new()
macro save(value) {
    list.push_mut(saved, value)
}
fn forbidden() -> u64 {
    emit.u8(1)
    return 0;
}
save forbidden()
emit.u32(0)
defer {
    store.u32(0, operand.eval(list.get(saved, 0)))
}
