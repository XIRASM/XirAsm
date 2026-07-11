const parts: list = split("mov,add,ret", ",")
const joined: string = join(parts, "|")
const singleton: list = split("kernel", ",")
const empty_parts: list = split("", ",")

assert(len(parts) == 3);
assert(list.get(parts, 0) == "mov");
assert(list.get(parts, 1) == "add");
assert(list.get(parts, 2) == "ret");
assert(joined == "mov|add|ret");
assert(len(singleton) == 1);
assert(list.get(singleton, 0) == "kernel");
assert(len(empty_parts) == 1);
assert(list.get(empty_parts, 0) == "");

for item in parts {
    emit.u8(len(item));
    emit.bytes(item);
}

emit.u8(len(joined));
emit.bytes(joined);
