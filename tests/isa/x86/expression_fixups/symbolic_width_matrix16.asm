origin(0)
x86.use16()

entry:
    add al, target
    add ax, target
    imul ax, ax, target
    push target
target:
    ret
