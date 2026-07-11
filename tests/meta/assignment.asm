// api-matrix-fixture: value = value + 1

let value = 40
value = value + 1

{
    let value = 1
    value = value + 1
    emit.u8(value);
}

fn bump(seed: integer) -> integer {
    let local = seed
    local = local + 1
    return local
}

emit.u8(value);
emit.u8(bump(value));
