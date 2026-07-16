import("../../../include/format/pe_export.inc");

let exports: list = pe_export_new()
exports = pe_export_use64_many(exports, list.of(""))
