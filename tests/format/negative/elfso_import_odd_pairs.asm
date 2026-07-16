import("../../../include/format/elfso_import.inc");

let imports: list = elfso_import_new()
imports = elfso_import_use64_pairs(imports, "libc.so.6", list.of("puts_slot"))
