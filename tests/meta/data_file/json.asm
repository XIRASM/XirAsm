// api-matrix-fixture: json.parse(
// api-matrix-fixture: json.file(

const cfg: map = json.file("config.json");
const raw: string = fs.read_text("config.json");
const parsed_again: map = json.parse(raw);
const values: list = map.get(cfg, "values");
const nested: map = map.get(parsed_again, "nested");

assert(map.get(cfg, "ok"));
emit.bytes(map.get(cfg, "name"));
emit.u8(map.get(cfg, "bits"));
emit.u8(list.get(values, 0));
emit.u8(list.get(values, 1));
emit.u8(list.get(values, 2));
emit.bytes(map.get(nested, "tag"));
