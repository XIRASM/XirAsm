let saved: list = list.new()
macro save(value) {
    list.push_mut(saved, value)
}
macro forward(value) {
    const ADDEND: u64 = 99
    save value
}
fn marked(value: u64) -> u64 {
    const stamp: string = sym.unique("evaluation")
    return value;
}
fn next_stamp() -> string {
    return sym.unique("evaluation");
}
fn indirect(index: u64) -> u64 {
    return operand.eval(list.get(saved, index));
}
fn indirect_stamp(index: u64) -> string {
    return operand.eval(list.get(saved, index));
}

let ADDEND: u64 = 4
forward marked(label_addr(future) + ADDEND)
save here() + ADDEND
save false && missing
save load.u32(label_addr(payload))
save sym.unique("evaluation")
ADDEND = 100

emit.u32(0)
future:
emit.u32(0)
emit.u32(0)
emit.u32(0)
payload:
emit.u32(0x44332211)

defer {
    const ADDEND: u64 = 1000
    let sentinel: u64 = 17
    store.u32(0, operand.eval(list.get(saved, 0)))
    store.u32(4, indirect(0))
    store.u32(8, operand.eval(list.get(saved, 1)))
    store.u32(12, operand.eval(list.get(saved, 3)))
    assert(!operand.eval(list.get(saved, 2)))
    assert(ADDEND == 1000 && sentinel == 17)
    sentinel = sentinel + 1
    assert(sentinel == 18)
    assert(operand.eval(list.get(saved, 4)) == "evaluation__2")
    assert(indirect_stamp(4) == "evaluation__3")
    assert(next_stamp() == "evaluation__4")
}
