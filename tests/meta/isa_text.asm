// api-matrix-fixture: isa(

x86.use64();

for i in list.of(0, 1, 2) {
    isa(sym.join(
        "vaddps ymm",
        to_string(i),
        ", ymm",
        to_string(i),
        ", ymm",
        to_string(i + 1)
    ));
}

isa("ret");
