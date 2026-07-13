fn produce() -> integer {
    let scratch: list = list.of(1)
    list.push_mut(scratch, 2);
    return len(scratch)
}

fn build() -> list {
    let items: list = list.of(7)
    if true {
        let items: list = list.of(8)
        list.push_mut(items, 9);
        assert(list.eq(items, list.of(8, 9)));
    }
    list.push_mut(items, produce());
    return items
}

let items: list = list.of(1)
const snapshot: list = items
list.push_mut(items, list.of(2));
list.set_mut(items, 0, 3);

let cfg: map = map.new()
map.set_mut(cfg, "items", items);
list.set_mut(items, 0, 4);

const result: list = build()
assert(list.eq(snapshot, list.of(1)));
assert(list.eq(items, list.of(4, list.of(2))));
assert(list.eq(map.get(cfg, "items"), list.of(3, list.of(2))));
assert(list.eq(result, list.of(7, 2)));

emit.u8(list.get(items, 0));
emit.u8(list.get(list.get(items, 1), 0));
emit.u8(list.get(map.get(cfg, "items"), 0));
emit.u8(list.get(list.get(map.get(cfg, "items"), 1), 0));
emit.u8(list.get(result, 0));
emit.u8(list.get(result, 1));
