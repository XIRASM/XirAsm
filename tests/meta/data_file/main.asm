// api-matrix-fixture: fs.exists(
// api-matrix-fixture: fs.read_text(
// api-matrix-fixture: fs.read_bytes(
// api-matrix-fixture: toml.parse(
// api-matrix-fixture: toml.file(

const cfg: map = toml.file("project.toml");
const target: map = map.get(cfg, "target");
const include_file: string = map.get(target, "include");
include(include_file);

const raw: string = fs.read_text("project.toml");
const parsed_again: map = toml.parse(raw);
assert(fs.exists("blob.bin"));
assert(contains(raw, "[target]"));

emit.bytes(fs.read_bytes("blob.bin"));
emit.u8(map.get(target, "bits"));
emit.bytes(map.get(parsed_again, "name"));
