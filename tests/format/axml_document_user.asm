// Data-driven AXML through the axml.inc facade: one namespace, one element
// carrying every attribute value kind, and a resource map row. The expected
// bytes pin the chunk layout, pool order, and UTF-16LE transcoder.
//
// This include is a DSL-layer format helper and is deliberately outside the
// Zig build: it is not listed in build.zig and carries no api-matrix markers.
// Assemble it directly and check the result with aapt2:
//   xirasm tests/format/axml_document_user.asm -o axml.bin
import("../../include/format/axml.inc");

let doc: map = axml_new()
doc = axml_pool_intern(doc, "first");
doc = axml_attr_resource_id(doc, "value", 0x01010024);
doc = axml_ns_start(doc, "ns", "uri://pkg");
doc = axml_start(doc, "root", list.of(
    axml_attr_string("value", "uri://pkg", "text"),
    axml_attr_int("count", "", 7),
    axml_attr_hex("mask", "", 0x80),
    axml_attr_bool("flag", "", axml_none),
    axml_attr_reference("icon", "uri://pkg", 0x7f020000)
));
doc = axml_start(doc, "leaf", list.new());
doc = axml_end(doc, "leaf");
doc = axml_end(doc, "root");
doc = axml_ns_end(doc, "ns", "uri://pkg");

const text_index: u64 = axml_pool_index(doc, "text")
assert(text_index == 5);

let document = bytes.new()
axml_build(document, doc);
emit.bytes(document);
