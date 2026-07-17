origin(0)
x86.use64()

const BIAS: u64 = 1

entry:
    add al, target
    add ax, target
    add eax, target
    add r11, target
    adc r11, target
    sbb r11, target
    and r11, target
    or r11, target
    xor r11, target
    sub r11, target
    cmp r11, target
    test r11, target
    imul r11, r11, target
    push target
    shl r11, target
    cmp qword [rel slot], target + BIAS
target:
    ret
slot:
    dq(0)
