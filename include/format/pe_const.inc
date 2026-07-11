// Shared PE/COFF constants for XIRASM format DSL helpers.
//
// Keep generic PE constants here so future COFF helpers can import the same
// names without pulling in the PE executable container.

const pe_magic_mz: u16 = 0x5a4d
const pe_signature: u32 = 0x00004550

const pe_machine_i386: u16 = 0x014c
const pe_machine_amd64: u16 = 0x8664

const pe_file_relocs_stripped: u16 = 0x0001
const pe_file_executable_image: u16 = 0x0002
const pe_file_large_address_aware: u16 = 0x0020
const pe_file_32bit_machine: u16 = 0x0100
const pe_file_system: u16 = 0x1000
const pe_file_dll: u16 = 0x2000

const pe_opt32_magic: u16 = 0x010b
const pe_opt64_magic: u16 = 0x020b

const pe_subsystem_unknown: u16 = 0
const pe_subsystem_native: u16 = 1
const pe_subsystem_gui: u16 = 2
const pe_subsystem_console: u16 = 3

const pe_dll_high_entropy_va: u16 = 0x0020
const pe_dll_dynamic_base: u16 = 0x0040
const pe_dll_nx_compat: u16 = 0x0100
const pe_dll_no_seh: u16 = 0x0400
const pe_dll_guard_cf: u16 = 0x4000
const pe_dll_terminal_server_aware: u16 = 0x8000

const pe_scn_cnt_code: u32 = 0x00000020
const pe_scn_cnt_init_data: u32 = 0x00000040
const pe_scn_cnt_uninit_data: u32 = 0x00000080
const pe_scn_mem_discardable: u32 = 0x02000000
const pe_scn_mem_execute: u32 = 0x20000000
const pe_scn_mem_read: u32 = 0x40000000
const pe_scn_mem_write: u32 = 0x80000000

const pe_text_chars: u32 = pe_scn_cnt_code | pe_scn_mem_read | pe_scn_mem_execute
const pe_data_chars: u32 = pe_scn_cnt_init_data | pe_scn_mem_read | pe_scn_mem_write
const pe_rdata_chars: u32 = pe_scn_cnt_init_data | pe_scn_mem_read
const pe_idata_chars: u32 = pe_scn_cnt_init_data | pe_scn_mem_read | pe_scn_mem_write
const pe_edata_chars: u32 = pe_scn_cnt_init_data | pe_scn_mem_read
const pe_reloc_chars: u32 = pe_scn_cnt_init_data | pe_scn_mem_read | pe_scn_mem_discardable
const pe_rsrc_chars: u32 = pe_scn_cnt_init_data | pe_scn_mem_read
const pe_bss_chars: u32 = pe_scn_cnt_uninit_data | pe_scn_mem_read | pe_scn_mem_write

const pe_dir_export: u64 = 0
const pe_dir_import: u64 = 1
const pe_dir_resource: u64 = 2
const pe_dir_exception: u64 = 3
const pe_dir_security: u64 = 4
const pe_dir_basereloc: u64 = 5
const pe_dir_debug: u64 = 6
const pe_dir_architecture: u64 = 7
const pe_dir_globalptr: u64 = 8
const pe_dir_tls: u64 = 9
const pe_dir_load_config: u64 = 10
const pe_dir_bound_import: u64 = 11
const pe_dir_iat: u64 = 12
const pe_dir_delay_import: u64 = 13
const pe_dir_com_descriptor: u64 = 14

const pe_section_header_size: u64 = 40
const pe_data_dir_count: u64 = 16
const pe_default_section_rows: u64 = 8
const pe_max_image_sections: u64 = 96

const pe_default_file_align: u64 = 0x200
const pe_default_section_align: u64 = 0x1000
const pe_default_image_base64: u64 = 0x0000000140000000
const pe_default_image_base32: u64 = 0x00400000
