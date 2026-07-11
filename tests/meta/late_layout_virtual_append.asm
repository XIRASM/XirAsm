// api-matrix-fixture: late_layout {

virtual.begin(0x3000);
scratch:
emit.u8(0x41);
emit.u8(0x42);
virtual.end();

emit.u8(0x10);

late_layout {
    emit.u8(load.u8(scratch));
    emit.u8(load.u8(scratch + 1));
}
