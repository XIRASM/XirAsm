origin(0)
x86.use64()

const PAGE_SIZE: u64 = 4096

entry:
    add r11, -130 + 1
    add r11, -129 + 1
    add r11, 126 + 1
    add r11, 127 + 1
    add r11, 254 + 1
    add r11, 255 + 1
    add r11, PAGE_SIZE - 1
    sub r11, 129 - 1
    cmp r11, 129 - 1
    push 129 - 1
    shl r11, 2 - 1
    ret
