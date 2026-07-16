import("../../../include/format/pe_import.inc");

let imports: map = pe_import_new()
imports = pe_import_use64_pairs(imports, "KERNEL32.DLL", list.of("exit_process"))
