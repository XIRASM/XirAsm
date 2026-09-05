// Minimal Mach-O 64 shared-library helpers.
//
// This layer emits a small MH_DYLIB with one exported `_entry` symbol.  It
// intentionally uses the classic export-trie load command only; imports,
// chained fixups, code signatures, and UUID generation stay outside this
// first usable facade.

import("macho_obj.inc");
import("macho_export.inc");

const macho_dylib_id_command_base_size: u64 = 24
const macho_dylib_export_command_size: u64 = 16
const macho_dylib_build_version_command_size: u64 = 24
const macho_dylib_export_entry_trie_size: u64 = 16

fn macho_dylib_header64_arm64(command_count: u64, command_size: u64) {
    macho_header64_arm64(macho_mh_dylib, command_count, command_size,
        macho_mh_dyldlink | macho_mh_twolevel | macho_mh_noundefs |
        macho_mh_no_reexported_dylibs);
}

fn macho_dylib_header64_x86_64(command_count: u64, command_size: u64) {
    macho_header64_x86_64(macho_mh_dylib, command_count, command_size,
        macho_mh_dyldlink | macho_mh_twolevel | macho_mh_noundefs |
        macho_mh_no_reexported_dylibs);
}

fn macho_dylib_id64(name: string, current_version: u64, compatibility_version: u64) {
    let name_size = len(name) + 1;
    let command_size = macho_align_up(macho_dylib_id_command_base_size + name_size, 8);
    emit.u32(macho_lc_id_dylib);
    emit.u32(command_size);
    emit.u32(macho_dylib_id_command_base_size);
    emit.u32(0);
    emit.u32(current_version);
    emit.u32(compatibility_version);
    db(name);
    db(0);
    pad(command_size - macho_dylib_id_command_base_size - name_size, 0);
}

// Emit one ordinary dependent-dylib load command. The command uses the same
// dylib record as LC_ID_DYLIB but is consumed as a dependency by dyld/ld64.
fn macho_dylib_load64(name: string, current_version: u64, compatibility_version: u64) {
    let name_size = len(name) + 1;
    let command_size = macho_align_up(macho_dylib_id_command_base_size + name_size, 8);
    emit.u32(macho_lc_load_dylib);
    emit.u32(command_size);
    emit.u32(macho_dylib_id_command_base_size);
    emit.u32(0);
    emit.u32(current_version);
    emit.u32(compatibility_version);
    db(name);
    db(0);
    pad(command_size - macho_dylib_id_command_base_size - name_size, 0);
}

fn macho_dylib_build_version64(minos: u64, sdk: u64) {
    emit.u32(macho_lc_build_version);
    emit.u32(macho_dylib_build_version_command_size);
    emit.u32(1);
    emit.u32(minos);
    emit.u32(sdk);
    emit.u32(0);
}

fn macho_dylib_exports_trie64(file_offset: u64, size: u64) {
    emit.u32(macho_lc_dyld_exports_trie);
    emit.u32(macho_dylib_export_command_size);
    emit.u32(file_offset);
    emit.u32(size);
}

// Export trie for exactly one `_entry` symbol at address 0x80:
// root(0, one child, edge "_entry", child offset 10), then terminal
// (flags 0, address 0x80), no children, and one alignment byte.
fn macho_dylib_export_entry_0x80() {
    emit.u8(0);
    emit.u8(1);
    db("_entry");
    emit.u8(0);
    emit.u8(10);
    emit.u8(3);
    emit.u8(0);
    emit.u8(0x80);
    emit.u8(1);
    emit.u8(0);
    emit.u8(0);
}
