let saved: list = list.new()
macro save(value) {
    list.push_mut(saved, value)
}
save unknown
emit.u32(0)
defer {
    const unknown: u64 = 7
    store.u32(0, operand.eval(list.get(saved, 0)))
}
