union Value {
    raw: u32 = 1
    byte: u8
}

const value: Value = Value { raw: 2 }
