import("../../include/format/pe_import.inc");

let imports: map = pe_import_new()
imports = pe_import_use64_many(imports, "KERNEL32.DLL", list.of("ExitProcess", "VirtualAlloc"))
imports = pe_import_use64_many(imports, "KERNEL32.DLL", list.of("ExitProcess", "VirtualAlloc"))
assert(len(map.get(imports, "KERNEL32.DLL")) == 2)
db(len(map.get(imports, "KERNEL32.DLL")))
