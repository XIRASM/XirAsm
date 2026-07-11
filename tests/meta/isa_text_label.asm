const done: string = sym.join("generated_", "done");

isa(sym.join("jmp ", done));
label.define(done);
isa("ret");
