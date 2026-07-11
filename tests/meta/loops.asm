for i in range(0, 4) {
    emit.u8(i);
}

while false {
    emit.u8(0xff);
}

emit.u8(0xaa);
