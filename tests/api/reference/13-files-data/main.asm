include("nested/reader.inc")

const banner: string = fs.read_text("banner.txt")

const json_config: map = json.file("config.json")
const json_again: map = json.parse(fs.read_bytes("config.json"))
const json_values: list = map.get(json_config, "values")
const json_nested: map = map.get(json_again, "nested")

assert(map.eq(json_config, json_again))
assert(map.get(json_config, "enabled"))
assert(map.has(json_config, "nothing"))

const toml_config: map = toml.file("config.toml")
const toml_again: map = toml.parse(fs.read_text("config.toml"))
const toml_target: map = map.get(toml_config, "target")
const toml_values: list = map.get(toml_again, "values")

assert(map.eq(toml_config, toml_again))
assert(map.get(toml_config, "enabled"))

emit.bytes(nested_range)
emit.bytes(banner)
emit.bytes(map.get(json_config, "name"))
emit.u8(map.get(json_config, "bits"))

for value in json_values {
    emit.u8(value)
}

emit.bytes(map.get(json_nested, "tag"))
emit.bytes(map.get(toml_config, "name"))
emit.u8(map.get(toml_target, "bits"))

for value in toml_values {
    emit.u8(value)
}
