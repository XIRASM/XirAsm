// Portable Mach-O constants used by the XIRASM format DSL helpers.

const macho_magic_64: u32 = 0xfeedfacf

const macho_cpu_arch_abi64: u32 = 0x01000000
const macho_cpu_type_x86: u32 = 7
const macho_cpu_type_x86_64: u32 = macho_cpu_type_x86 | macho_cpu_arch_abi64
const macho_cpu_type_arm: u32 = 12
const macho_cpu_type_arm64: u32 = macho_cpu_type_arm | macho_cpu_arch_abi64
const macho_cpu_subtype_x86_64_all: u32 = 3
const macho_cpu_subtype_x86_64_h: u32 = 8
const macho_cpu_subtype_arm64_all: u32 = 0
const macho_cpu_subtype_arm64_v8: u32 = 1
const macho_cpu_subtype_arm64e: u32 = 2
const macho_cpu_subtype_lib64: u32 = 0x80000000

const macho_page_size_x86_64: u64 = 0x1000
const macho_page_size_arm64: u64 = 0x4000

const macho_platform_macos: u32 = 1

const macho_mh_object: u32 = 1
const macho_mh_execute: u32 = 2
const macho_mh_dylib: u32 = 6

const macho_mh_noundefs: u32 = 0x00000001
const macho_mh_dyldlink: u32 = 0x00000004
const macho_mh_twolevel: u32 = 0x00000080
const macho_mh_subsections_via_symbols: u32 = 0x00002000
const macho_mh_no_reexported_dylibs: u32 = 0x00100000
const macho_mh_pie: u32 = 0x00200000

const macho_lc_segment_64: u32 = 0x19
const macho_lc_symtab: u32 = 0x02
const macho_lc_dysymtab: u32 = 0x0b
const macho_lc_load_dylib: u32 = 0x0c
const macho_lc_id_dylib: u32 = 0x0d
const macho_lc_load_dylinker: u32 = 0x0e
const macho_lc_code_signature: u32 = 0x1d
const macho_lc_dyld_info_only: u32 = 0x80000022
const macho_lc_main: u32 = 0x80000028
const macho_lc_build_version: u32 = 0x32
const macho_lc_dyld_exports_trie: u32 = 0x80000033
const macho_lc_dyld_chained_fixups: u32 = 0x80000034

const macho_vm_prot_read: u32 = 1
const macho_vm_prot_write: u32 = 2
const macho_vm_prot_execute: u32 = 4

const macho_s_regular: u32 = 0
const macho_s_zerofill: u32 = 1
const macho_s_non_lazy_symbol_pointers: u32 = 6
const macho_s_symbol_stubs: u32 = 8
const macho_s_attr_pure_instructions: u32 = 0x80000000
const macho_s_attr_some_instructions: u32 = 0x00000400

const macho_bind_type_pointer: u8 = 1
const macho_bind_opcode_done: u8 = 0x00
const macho_bind_opcode_set_dylib_ordinal_imm: u8 = 0x10
const macho_bind_opcode_set_symbol_trailing_flags_imm: u8 = 0x40
const macho_bind_opcode_set_type_imm: u8 = 0x50
const macho_bind_opcode_set_segment_and_offset_uleb: u8 = 0x70
const macho_bind_opcode_do_bind: u8 = 0x90

const macho_n_stab: u8 = 0xe0
const macho_n_pext: u8 = 0x10
const macho_n_type: u8 = 0x0e
const macho_n_ext: u8 = 0x01
const macho_n_undef: u8 = 0x00
const macho_n_sect: u8 = 0x0e

const macho_arm64_reloc_unsigned: u32 = 0
const macho_arm64_reloc_subtractor: u32 = 1
const macho_arm64_reloc_branch26: u32 = 2
const macho_arm64_reloc_page21: u32 = 3
const macho_arm64_reloc_pageoff12: u32 = 4
const macho_arm64_reloc_got_load_page21: u32 = 5
const macho_arm64_reloc_got_load_pageoff12: u32 = 6
const macho_arm64_reloc_pointer_to_got: u32 = 7
const macho_arm64_reloc_tlvp_load_page21: u32 = 8
const macho_arm64_reloc_tlvp_load_pageoff12: u32 = 9
const macho_arm64_reloc_addend: u32 = 10
const macho_arm64_reloc_authenticated_pointer: u32 = 11

const macho_x86_64_reloc_unsigned: u32 = 0
const macho_x86_64_reloc_signed: u32 = 1
const macho_x86_64_reloc_branch: u32 = 2
