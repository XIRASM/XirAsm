region.begin("text", 0x1000, 0)
x86.use64()

entry:
    jmp near data_target
    call data_target
    jne near data_target
    call data_target + 1
    jmp near data_target + 2

output.section("data", 0x2000)
data_target:
    ret
    nop
    nop
