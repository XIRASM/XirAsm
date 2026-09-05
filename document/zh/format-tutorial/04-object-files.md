# 4. COFF 和 ELF 目标文件

目标文件不是操作系统直接加载的程序，而是交给链接器继续处理的中间文件：它描述节、对链接器可见的符号，以及需要链接器回填的占位字段。`format.inc` 用同一套流程生成 COFF32、COFF64、ELF32、ELF64（x86-64 与 AArch64）以及 Mach-O 64 可重定位目标文件。

目标文件没有普通可执行入口，不要调用 `format_entry_mut`。工作流程始终是：

1. 声明节；
2. 在节里写占位字节和真实数据；
3. 用符号列表描述要暴露给链接器的标签；
4. 用重定位列表描述需要链接器修正的占位；
5. 用 `format_*_tables_mut` 把两张表挂到配置上，然后 finish。

## COFF 目标文件模板

COFF 目标文件支持 `format_code`、`format_data`、`format_uninitialized_data` 三类节。节名必须不超过 8 字节。

```asm
import("format/format.inc");

// 面向 Windows/MSVC 风格链接器的 64 位 COFF 目标文件。
let object: map = format_coff64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(object);

// .text 中包含一个 call 位移占位。
format_section_begin(object, ".text");
text_start:
main:
    db(0xe8);
call_disp:
    dd(0);
    xor eax, eax
    ret
format_section_end(object, ".text");

format_section_begin(object, ".data");
data_start:
answer:
    dd(42);
format_section_end(object, ".data");

format_section_begin(object, ".bss");
bss_start:
scratch:
    rb(64);
format_section_end(object, ".bss");

// 声明公开符号和外部符号。
const symbols: list = list.of(
    format_coff_public("main", ".text", text_start, main, coff_sym_type_function),
    format_coff_public("answer", ".data", data_start, answer, coff_sym_type_null),
    format_coff_public("scratch", ".bss", bss_start, scratch, coff_sym_type_null),
    format_coff_extern("puts", coff_sym_type_function)
)

// 链接器将用 32 位相对调用位移回填 call_disp。
const relocs: list = list.of(
    format_coff_reloc(".text", text_start, call_disp, "puts", coff_rel_amd64_rel32)
)
format_coff_tables_mut(object, symbols, relocs)
format_finish(object);
```

`format_coff_public` 的地址参数是符号标签，`section_start` 是该符号所在节的起始标签，写进符号表的值就是两者之差。重定位的地址参数是需要链接器修正的占位位置——上例的 `call_disp` 就是 `call rel32` 的 4 字节位移。

COFF 常用相对调用重定位：

| 位宽 | 重定位 |
| --- | --- |
| 32 位 | `coff_rel_i386_rel32` |
| 64 位 | `coff_rel_amd64_rel32` |

## ELF 目标文件模板

ELF 目标文件同样支持代码、数据和 BSS 节，节名可以超过 8 字节。

```asm
import("format/format.inc");

let object: map = format_elfobj64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".rodata", format_data | format_readable)
    )
)
format_begin(object);

format_section_begin(object, ".text");
text_start:
_start:
    db(0xe8);
call_disp:
    dd(0);
    xor eax, eax
    ret
format_section_end(object, ".text");

format_section_begin(object, ".bss");
bss_start:
scratch:
    reserve(64);
format_section_end(object, ".bss");

format_section_begin(object, ".rodata");
data_start:
answer:
    dd(42);
format_section_end(object, ".rodata");

// ELF 公开符号需要名称、节、节起始、地址、大小和类型。
const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 8, elfobj_stt_func),
    format_elfobj_public("scratch", ".bss", bss_start, scratch, 64, elfobj_stt_object),
    format_elfobj_public("answer", ".rodata", data_start, answer, 4, elfobj_stt_object),
    format_elfobj_extern("puts", elfobj_stt_func)
)

// x86-64 的 PLT 调用通常使用 R_X86_64_PLT32，addend 为 -4。
const relocs: list = list.of(
    format_elfobj_reloc(".text", text_start, call_disp, "puts", elf_r_x86_64_plt32, 0xfffffffffffffffc)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
```

ELF64 重定位是带显式 addend 的 RELA 记录。`call rel32` 的 addend `-4`（`0xfffffffffffffffc`）就是位移字段本身的大小，来自 x86-64 psABI 的约定。

### 选择 ELF 机器类型

| 构造函数 | `e_machine` | 说明 |
| --- | --- | --- |
| `format_elfobj32(sections)` | `EM_386` | 同时把汇编器切换到 32 位 x86 文本模式 |
| `format_elfobj64(sections)` | `EM_X86_64` | 同时把汇编器切换到 64 位 x86 文本模式 |
| `format_elfobj64_aarch64(sections)` | `EM_AARCH64` | 面向 arm64 Linux/BSD 目标 |
| `format_elfobj64_machine(sections, machine)` | 显式指定 | 接受 `elf_machine_x86_64` 或 `elf_machine_aarch64` |

AArch64 形式不会选择任何 x86 文本模式。请把 A64 指令字当作数据发射——用 `emit.u32` 或 AArch64 DSL 层——并在重定位中使用来自 `elf_const.inc` 的 AArch64 类型：

```asm
const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 16, elfobj_stt_func),
    format_elfobj_public("answer", ".data", data_start, answer, 8, elfobj_stt_object),
    format_elfobj_extern("printf", elfobj_stt_func)
)

// 每条重定位描述链接器要修正的占位字或指针字段；
// AArch64 使用 RELA，因此 addend 是显式的。
const relocs: list = list.of(
    // bl printf：R_AARCH64_CALL26。
    format_elfobj_reloc(".text", text_start, call_site, "printf", elf_r_aarch64_call26, 0),
    // adrp x0, answer：页基址部分。
    format_elfobj_reloc(".text", text_start, page_site, "answer", elf_r_aarch64_adr_prel_pg_hi21, 0),
    // add x0, x0, :lo12:answer：低 12 位部分。
    format_elfobj_reloc(".text", text_start, lo12_site, "answer", elf_r_aarch64_add_abs_lo12_nc, 0),
    // .xword printf：R_AARCH64_ABS64。
    format_elfobj_reloc(".data", data_start, ptr_slot, "printf", elf_r_aarch64_abs64, 0)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
```

`elf_const.inc` 提供常用的 AArch64 类型：`elf_r_aarch64_abs64`、`elf_r_aarch64_abs32`、`elf_r_aarch64_adr_prel_lo21`、`elf_r_aarch64_adr_prel_pg_hi21`、`elf_r_aarch64_add_abs_lo12_nc`、`elf_r_aarch64_ldst{8,16,32,64}_abs_lo12_nc` 系列、`elf_r_aarch64_condbr19`、`elf_r_aarch64_jump26`、`elf_r_aarch64_call26`，以及 GOT 形式的 `elf_r_aarch64_adr_got_page` 和 `elf_r_aarch64_ld64_got_lo12_nc`。指向同一符号的 `adrp`/`add` 配对会同时使用页重定位和低 12 位重定位。

ELF32 使用 `format_elfobj32`。常用的 32 位相对调用重定位是 `elf_r_386_pc32`。

## Mach-O 目标文件

`format_macho64_object(target, sections)` 为选定的 CPU 目标生成 `MH_OBJECT` 可重定位文件（详见 [macOS Mach-O](06-macos-macho.md)）。它与上面的模板共享节生命周期；调用 `format_macho64_tables_mut` 挂上符号表后，符号表、重定位和 `LC_SYMTAB` 都由 facade 自动管理。目标文件符号和重定位使用 `format_macho64_public`、`format_macho64_extern`、`format_macho64_reloc` 以及 ISA 便捷形式 `format_macho64_arm64_reloc`；下面的汇总表列出了它们的签名，Mach-O 一章有完整示例。

## API 摘要

| 家族 | 函数 | 用途 |
| --- | --- | --- |
| COFF | `format_coff32(sections)` / `format_coff64(sections)` | 创建 COFF 目标文件配置 |
| COFF | `format_coff_public(name, section_name, section_start, address, sym_type)` | 声明公开符号 |
| COFF | `format_coff_extern(name, sym_type)` | 声明外部符号 |
| COFF | `format_coff_reloc(section_name, section_start, address, symbol_name, reloc_type)` | 声明需要链接器修正的字段 |
| COFF | `format_coff_tables_mut(plan, symbols, relocs)` | 把 COFF 符号表和重定位表挂到配置上 |
| ELF | `format_elfobj32(sections)` / `format_elfobj64(sections)` | 创建 x86 目标文件配置 |
| ELF | `format_elfobj64_aarch64(sections)` | 创建 AArch64 目标文件配置 |
| ELF | `format_elfobj64_machine(sections, machine)` | 以显式机器类型创建目标文件配置 |
| ELF | `format_elfobj_public(name, section_name, section_start, address, symbol_size, symbol_type)` | 声明公开符号 |
| ELF | `format_elfobj_extern(name, symbol_type)` | 声明外部符号 |
| ELF | `format_elfobj_reloc(section_name, section_start, address, symbol_name, reloc_type, addend)` | 声明需要链接器修正的字段 |
| ELF | `format_elfobj_tables_mut(plan, symbols, relocs)` | 把 ELF 符号表和重定位表挂到配置上 |
| Mach-O | `format_macho64_object(target, sections)` | 创建 Mach-O 目标文件配置 |
| Mach-O | `format_macho64_target_arm64(minos, sdk)` / `format_macho64_target_x86_64(minos, sdk)` | 选择 CPU 目标和 macOS 版本 |
| Mach-O | `format_macho64_public(name, section_name, section_start, address, symbol_type)` | 声明公开符号 |
| Mach-O | `format_macho64_extern(name)` | 声明外部符号 |
| Mach-O | `format_macho64_reloc(section_name, section_start, address, symbol_name, pcrel, length, reloc_type)` | 声明需要链接器修正的字段 |
| Mach-O | `format_macho64_arm64_reloc(section_name, section_start, address, symbol_name, reloc_type)` | 声明 AArch64 重定位字段，`pcrel`/`length` 自动推导 |
| Mach-O | `format_macho64_tables_mut(plan, symbols, relocs)` | 把 Mach-O 符号表和重定位表挂到配置上 |

重定位字段是文件中已经写出的占位字节。先写占位，再用 `format_*_reloc` 描述这段占位应该由链接器怎样修正。
