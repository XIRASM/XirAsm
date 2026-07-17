region.begin("text", 0x1000, 0)
x86.use64()

entry:
    mov eax, data_target
    add r11, data_target + 4
    mov eax, [rel data_target]

output.section("data", 0x2000)
data_target:
    ret
