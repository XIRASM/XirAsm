// Android framework resource IDs.
//
// The table itself is the data file beside this include, generated from the
// platform jar (android-37.0) through aapt2. Reading it is one native TOML
// parse, so importing this file costs nothing and a program pays for the
// table only when it asks for it: 17 types, 3037 entries.
//
//   const ids: map = android_framework_ids()
//   app = apk_use_theme_id(app, android_style_id(ids, "Theme.DeviceDefault"));
//
// Load the table once and pass it to the lookups: each lookup is then a map
// read rather than another parse.

const android_framework_data: string = "format/android/generated/framework_ids.toml"

fn android_framework_ids() -> map {
    return toml.file(android_framework_data)
}

// Resource names carry dots (`Theme.DeviceDefault`); the table stores them
// flat with '~' in place of the dot.
fn android_key(name: string) -> string {
    return replace(name, ".", "~")
}

fn android_id(ids: map, type_name: string, entry_name: string) -> u64 {
    assert(map.has(ids, type_name), "android framework resource type is unknown");
    const entries: map = map.get(ids, type_name)
    const key: string = android_key(entry_name)
    assert(map.has(entries, key), "android framework resource name is unknown");
    return map.get(entries, key)
}

fn android_anim_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "anim", entry_name)
}

fn android_animator_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "animator", entry_name)
}

fn android_array_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "array", entry_name)
}

fn android_attr_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "attr", entry_name)
}

fn android_bool_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "bool", entry_name)
}

fn android_color_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "color", entry_name)
}

fn android_dimen_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "dimen", entry_name)
}

fn android_drawable_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "drawable", entry_name)
}

fn android_id_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "id", entry_name)
}

fn android_integer_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "integer", entry_name)
}

fn android_interpolator_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "interpolator", entry_name)
}

fn android_layout_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "layout", entry_name)
}

fn android_mipmap_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "mipmap", entry_name)
}

fn android_raw_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "raw", entry_name)
}

fn android_string_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "string", entry_name)
}

fn android_style_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "style", entry_name)
}

fn android_transition_id(ids: map, entry_name: string) -> u64 {
    return android_id(ids, "transition", entry_name)
}
