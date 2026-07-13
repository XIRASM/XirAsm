if false {
    emit.u8(0xee);
} else if true {
    emit.u8(0x11);
} else {
    emit.u8(0xff);
}

if false {
    emit.u8(0xdd);
} else if false {
    emit.u8(0xcc);
} else {
    emit.u8(0x22);
}

for i in range(0, 6) {
    if i == 1 {
        // api-matrix-fixture: continue;
        continue;
    }
    if i == 4 {
        // api-matrix-fixture: break;
        break;
    }
    emit.u8(i);
}

const values: list = list.of(5, 6, 7, 8)
for value in values {
    if value == 6 {
        continue;
    }
    if value == 8 {
        break;
    }
    emit.u8(value);
}

let counter = 0
while true {
    counter = counter + 1
    if counter == 2 {
        continue;
    }
    emit.u8(counter);
    if counter == 4 {
        break;
    }
}

for outer in range(0, 3) {
    for inner in range(0, 3) {
        if inner == 1 {
            break;
        }
        emit.u8(outer + 0x10);
    }
}

finalizer_slots:
emit.u32(0);

defer {
    let index = 0
    while true {
        index = index + 1
        if index == 2 {
            continue;
        }
        store.u8(finalizer_slots + index - 1, index);
        if index == 4 {
            break;
        }
    }
}
