// Resource-table fixture through the arsc.inc facade. The builder canonicalizes
// type order, entry order, configuration order, and the value pool, so this
// document is declared out of order on purpose and still produces the same
// bytes an aapt2 link of the same resources produces. The size assertion pins
// the whole ResTable layout (header, pools, type specs, type chunks).
//
// This include is a DSL-layer format helper and is deliberately outside the
// Zig build: it is not listed in build.zig and carries no api-matrix markers.
// Assemble it directly and compare the output with aapt2 2.20:
//   xirasm tests/format/arsc_document_user.asm -o arsc.bin
import("../../include/format/arsc.inc");

let tbl: map = arsc_new("com.example.xirasm.res", 0x7f)
tbl = arsc_file_locale(tbl, "mipmap", "ic_launcher", "hdpi", "zh", "res/mipmap-zh-hdpi-v4/ic_launcher.png")
tbl = arsc_file(tbl, "mipmap", "ic_launcher", "hdpi", "res/mipmap-hdpi-v4/ic_launcher.png")
tbl = arsc_string(tbl, "app_name", "XIRASM Icons")
tbl = arsc_file(tbl, "mipmap", "ic_launcher", "mdpi", "res/mipmap-mdpi-v4/ic_launcher.png")
tbl = arsc_string_locale(tbl, "app_name", "XIRASM Icons ZH", "zh")
tbl = arsc_int(tbl, "integer", "version_slot", 3)
tbl = arsc_bool(tbl, "bool", "enabled", true)
tbl = arsc_reference(tbl, "xml", "alias", 0x7f010000)

// Resource ids follow the canonical order, not the declaration order: type ids
// are assigned by sorted type name (bool, integer, mipmap, string, xml).
let label_id: u64 = 0
arsc_resolve_id(label_id, tbl, "string", "app_name");
assert(label_id == 0x7f040000);

let icon_id: u64 = 0
arsc_resolve_id(icon_id, tbl, "mipmap", "ic_launcher");
assert(icon_id == 0x7f030000);

let blob = bytes.new()
arsc_build(blob, tbl);
assert(len(blob) == 1656, "arsc fixture layout drifted");
emit.bytes(blob);
