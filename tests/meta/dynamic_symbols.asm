// api-matrix-fixture: sym.join(
// api-matrix-fixture: sym.unique(
// api-matrix-fixture: label.define(

const entry: string = sym.join("dyn_", "entry");
label.define(entry);
emit.u8(0xa1);
emit.u8(label_addr(entry) - region_base());

const local0: string = sym.unique("tmp");
label.define(local0);
emit.u8(0xb2);
emit.u8(label_addr(local0) - region_base());

const local1: string = sym.unique("tmp");
label.define(local1);
emit.u8(0xc3);
emit.u8(label_addr(local1) - region_base());
