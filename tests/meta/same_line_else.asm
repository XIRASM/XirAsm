if (true) {
    emit.u8(0x11);
} else {
    emit.u8(0xee);
}

if (false) {
    emit.u8(0xdd);
} else {
    emit.u8(0x22);
}
