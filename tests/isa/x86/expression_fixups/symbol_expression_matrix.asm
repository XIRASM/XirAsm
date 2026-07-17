origin(0)
x86.use64()

const DELTA: u64 = 4

entry:
    mov eax, target
    add r11, target + DELTA
    sub r11, target - DELTA
    cmp r11, (target + DELTA) - 1
    mov eax, [rel target + DELTA]
    lea rbx, [rel target - DELTA]
target:
    ret
