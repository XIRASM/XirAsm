const source: string = "load rax, [rbx+(rcx*4)]"
const source_tokens: list = tokens.of(source)
const source_copy: list = tokens.of(source_tokens)
const logical_tokens: list = tokens.of("left  && middle ||  right")

assert(len(source_tokens) == 12);
assert(list.eq(source_tokens, source_copy));
assert(tokens.join(source_tokens) == source);
assert(tokens.join(logical_tokens) == "left&&middle||right");

const load_match: map = match.tokens(
    "=load destination:name =, address:tokens",
    source_tokens
)
const load_captures: map = map.get(load_match, "captures")

assert(map.get(load_match, "ok"));
assert(map.get(load_captures, "destination") == "rax");
assert(tokens.join(map.get(load_captures, "address")) == "[rbx+(rcx*4)]");

const set_pattern: list = list.of(
    "=set",
    "target:name",
    "=,",
    "value:int"
)
const set_match: map = match.tokens(
    set_pattern,
    tokens.of("set count, 0x2a")
)
const set_captures: map = map.get(set_match, "captures")

assert(map.get(set_match, "ok"));
assert(map.get(set_captures, "target") == "count");
assert(map.get(set_captures, "value") == 42);

const operator_match: map = match.tokens(
    "left:name operator:token right:name",
    "count + step"
)
const operator_captures: map = map.get(operator_match, "captures")

assert(map.get(operator_match, "ok"));
assert(map.get(operator_captures, "operator") == "+");

const quoted_match: map = match.tokens("=db text:quoted", "db 'OK'")
const quoted_captures: map = map.get(quoted_match, "captures")

assert(map.get(quoted_match, "ok"));
assert(map.get(quoted_captures, "text") == "OK");

const backtrack_match: map = match.tokens(
    "prefix:tokens value:int",
    "name 42"
)
const backtrack_captures: map = map.get(backtrack_match, "captures")

assert(map.get(backtrack_match, "ok"));
assert(tokens.join(map.get(backtrack_captures, "prefix")) == "name");
assert(map.get(backtrack_captures, "value") == 42);

const empty_match: map = match.tokens("=call arguments:tokens", "call")
const empty_captures: map = map.get(empty_match, "captures")

assert(map.get(empty_match, "ok"));
assert(len(map.get(empty_captures, "arguments")) == 0);

const miss: map = match.tokens("value:int", "name")
assert(!map.get(miss, "ok"));
assert(len(map.keys(map.get(miss, "captures"))) == 0);

emit.u8(len(source_tokens));
emit.bytes(tokens.join(source_copy));
emit.bytes(map.get(load_captures, "destination"));
emit.u8(map.get(set_captures, "value"));
emit.bytes(map.get(quoted_captures, "text"));
emit.bytes(tokens.join(map.get(backtrack_captures, "prefix")));
emit.u8(len(map.get(empty_captures, "arguments")));
