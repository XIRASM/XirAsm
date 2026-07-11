origin(0x400000);

entry:
    jmp short conditional
conditional:
    jne target
    ret
target:
    ret
