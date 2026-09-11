// A virtual region is scratch: its bytes enter the file only where the source
// copies them, and the copy happens before references are patched. An
// instruction that needs a resolved field is therefore refused where it is
// written, rather than letting the encoded placeholder reach the file.
x86.use64();

virtual.begin(0x3000);
loop:
jmp loop
const blob: bytes = load.bytes(0x3000, 2)
virtual.end();

emit.bytes(blob);
