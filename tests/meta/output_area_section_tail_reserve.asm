// output.section follows section-tail semantics: the previous tail reserve is
// not materialized before the next initialized output area.

emit.u8(0x41);
reserve(3);
output.section("next", 0x2000);
emit.u8(0x42);
