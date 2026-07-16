const base_imports: map = map.new()
const imports: map = map.set(
    base_imports,
    "kernel32.dll",
    list.of(
        map.set(
            map.set(map.new(), "name", "ExitProcess"),
            "slot",
            "ExitProcess"
        )
    )
)

fn import_symbol(dll: string, slot: string) -> string {
    return sym.join(
        "pe_import_",
        replace(
            replace(
                replace(lower(dll), ".", "_"),
                "-",
                "_"
            ),
            " ",
            "_"
        ),
        "_",
        replace(slot, ".", "_")
    )
}

packed struct Pair {
    lo: u8,
    hi: u8,
}

assert(len(imports) == 1);
assert(list.eq(map.get(imports, "kernel32.dll"), list.of(map.set(map.set(map.new(), "name", "ExitProcess"), "slot", "ExitProcess"))));
emit.u8(lengthof(import_symbol("KERNEL32.DLL", "ExitProcess")));
emit.bytes(pack(
    Pair {
        lo: 3,
        hi: 4,
    }
));
