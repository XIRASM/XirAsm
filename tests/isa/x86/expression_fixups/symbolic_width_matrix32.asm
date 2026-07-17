origin(0)
x86.use32()

entry:
    add al, target
    add ax, target
    add eax, target
    imul eax, eax, target
    push target
target:
    ret
