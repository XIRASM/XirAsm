# 4. COFF 和 ELF 目标文件

目标文件不是操作系统直接加载的程序，而是交给链接器继续处理的中间文件。普通格式层可以生成 COFF32/COFF64 和 ELF32/ELF64 目标文件，并让你声明公开符号、外部符号和重定位字段。

目标文件没有普通可执行入口，不要调用 `format_entry_mut`。它们的关键是：

- 先声明节；
- 在节里写占位字节和真实数据；
- 用符号表描述哪些标签要暴露给链接器；
- 用重定位表描述哪些字节需要链接器修正。

## COFF 目标文件

COFF 普通层支持 `format_code`、`format_data`、`format_uninitialized_data` 三类节。节名必须不超过 8 字节。

```asm
import("format/format.inc");

let object: map = format_coff64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(object);

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

const symbols: list = list.of(
    format_coff_public("main", ".text", text_start, main, coff_sym_type_function),
    format_coff_public("answer", ".data", data_start, answer, coff_sym_type_null),
    format_coff_public("scratch", ".bss", bss_start, scratch, coff_sym_type_null),
    format_coff_extern("puts", coff_sym_type_function)
)
const relocs: list = list.of(
    format_coff_reloc(".text", text_start, call_disp, "puts", coff_rel_amd64_rel32)
)
format_coff_tables_mut(object, symbols, relocs)
format_finish(object);
```

`format_coff_public` 的地址参数是符号标签；`section_start` 是该符号所在节的起始标签。重定位的地址参数是需要链接器修正的字段位置，例如上面 `call_disp` 对应 `call rel32` 的 4 字节位移占位。

## ELF 目标文件

ELF 目标文件普通层同样支持代码、数据和 BSS 节。ELF 节名可以长于 8 字节。

```asm
import("format/format.inc");

let object: map = format_elfobj64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".rodata.long", format_data | format_readable)
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

format_section_begin(object, ".rodata.long");
data_start:
answer:
    dd(42);
format_section_end(object, ".rodata.long");

const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 8, elfobj_stt_func),
    format_elfobj_public("scratch", ".bss", bss_start, scratch, 64, elfobj_stt_object),
    format_elfobj_public("answer", ".rodata.long", data_start, answer, 4, elfobj_stt_object),
    format_elfobj_extern("puts", elfobj_stt_func)
)
const relocs: list = list.of(
    format_elfobj_reloc(".text", text_start, call_disp, "puts", elf_r_x86_64_plt32, 0xfffffffffffffffc)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
```

ELF RELA 型重定位需要显式 addend。x86-64 的 `call rel32` 常见 addend 是 `-4` 的 64 位补码，也就是 `0xfffffffffffffffc`。

## API 摘要

| 家族 | 函数 | 用途 |
| --- | --- | --- |
| COFF | `format_coff32(sections)` / `format_coff64(sections)` | 创建 COFF 目标文件配置 |
| COFF | `format_coff_public(name, section_name, section_start, address, sym_type)` | 声明公开符号 |
| COFF | `format_coff_extern(name, sym_type)` | 声明外部符号 |
| COFF | `format_coff_reloc(section_name, section_start, address, symbol_name, reloc_type)` | 声明需要链接器修正的字段 |
| COFF | `format_coff_tables_mut(plan, symbols, relocs)` | 把 COFF 符号表和重定位表挂到配置上 |
| ELF | `format_elfobj32(sections)` / `format_elfobj64(sections)` | 创建 ELF 目标文件配置 |
| ELF | `format_elfobj_public(name, section_name, section_start, address, symbol_size, symbol_type)` | 声明公开符号 |
| ELF | `format_elfobj_extern(name, symbol_type)` | 声明外部符号 |
| ELF | `format_elfobj_reloc(section_name, section_start, address, symbol_name, reloc_type, addend)` | 声明需要链接器修正的字段 |
| ELF | `format_elfobj_tables_mut(plan, symbols, relocs)` | 把 ELF 符号表和重定位表挂到配置上 |

重定位字段是文件中已经写出的占位字节。先写占位，再用 `format_*_reloc` 描述这段占位应该由链接器怎样修正。
