fn emit_pair(value: u8) {
    emit.u8(value)
    emit.u8(value + 1)
}

fn choose(value: u64, limit: u64) -> u64 {
    if value > limit {
        return limit
    } else {
        return value
    }
}

emit_pair(1)
emit.u8(choose(9, 5))

const enabled = true

if enabled {
    emit.u8(0xaa)
} else {
    emit.u8(0xff)
}

let counter = 0

while counter < 2 {
    emit.u8(0x10 + counter)
    counter = counter + 1
}

for index in range(0, 2) {
    emit.u8(0x20 + index)
}

const values: list = list.of(0x30, 0x31)

for value in values {
    emit.u8(value)
}
