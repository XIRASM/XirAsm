pub const types = @import("types.zig");
pub const spec = @import("spec.zig");
pub const section = @import("section.zig");
pub const module = @import("module.zig");
pub const text = @import("text.zig");
pub const text_tables = @import("text_tables.zig");

pub const Word = types.Word;
pub const Id = types.Id;
pub const Section = section.Section;
pub const Module = module.Module;
pub const Version = module.Version;

test {
    _ = types;
    _ = spec;
    _ = section;
    _ = module;
    _ = text;
    _ = text_tables;
}
