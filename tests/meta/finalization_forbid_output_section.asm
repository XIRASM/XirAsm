emit.u8(0x11);

defer {
    output.section("late", 0x1000);
}
