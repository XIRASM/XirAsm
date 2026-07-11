const line: string = "mov rax, [rbx+4]"
const tokens: list = tokens.of(line)
const rendered: string = tokens.join(tokens)
const mov_match: map = match.tokens("=mov dst:name =, src:tokens", line)
const captures: map = map.get(mov_match, "captures")
const src: list = map.get(captures, "src")
const load_match: map = match.tokens("=load rd:name =, imm:int", "load r1, 42")
const load_caps: map = map.get(load_match, "captures")
const quoted_match: map = match.tokens("=db text:quoted", "db 'OK'")
const quoted_caps: map = map.get(quoted_match, "captures")
const miss: map = match.tokens("=add dst:name =, src:name", line)
const typed_miss: map = match.tokens("value:int", "name")
const backtrack_match: map = match.tokens("prefix:tokens value:int", "name 42")
const backtrack_caps: map = map.get(backtrack_match, "captures")
const comparison_match: map = match.tokens("expr:tokens", "left < right")
const comparison_caps: map = map.get(comparison_match, "captures")
const logical_match: map = match.tokens(
    "left:name =&& middle:name =|| right:name",
    "a && b || c"
)

assert(rendered == line);
assert(map.get(mov_match, "ok"));
assert(map.get(captures, "dst") == "rax");
assert(tokens.join(src) == "[rbx+4]");
assert(map.get(load_caps, "rd") == "r1");
assert(map.get(load_caps, "imm") == 42);
assert(map.get(quoted_caps, "text") == "OK");
assert(!map.get(miss, "ok"));
assert(!map.get(typed_miss, "ok"));
assert(map.get(backtrack_match, "ok"));
assert(tokens.join(map.get(backtrack_caps, "prefix")) == "name");
assert(map.get(backtrack_caps, "value") == 42);
assert(map.get(comparison_match, "ok"));
assert(tokens.join(map.get(comparison_caps, "expr")) == "left<right");
assert(map.get(logical_match, "ok"));

emit.u8(len(map.get(captures, "dst")));
emit.bytes(map.get(captures, "dst"));
emit.u8(len(tokens.join(src)));
emit.bytes(tokens.join(src));
emit.u8(map.get(load_caps, "imm"));
emit.u8(len(map.get(quoted_caps, "text")));
emit.bytes(map.get(quoted_caps, "text"));
emit.bytes(map.get_or(miss, "missing", b"MISS"));
