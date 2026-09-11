// Scratch code that carries references enters the file through region.place:
// the virtual region becomes a real output region, so its instructions keep
// their fragments, labels, and fixups, and those resolve against the placed
// address instead of shipping the encoded placeholder.
//
// `call main_target` is an external reference and `jmp gen_start` is an internal
// one; both must be correct in the file.

x86.use64();

main_target:
emit.u8(0x90)

virtual.begin(0x9000);
gen_start:
call main_target
jmp gen_start
virtual.end();

late_layout {
    region.place("gen_start", 0x8000, 0x10)
    // The placed region is the active one now, positioned after the content it
    // already carries, so further output continues inside it.
    emit.u8(0xcc)
}
