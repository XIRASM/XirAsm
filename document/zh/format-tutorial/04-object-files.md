# 4. COFF 和 ELF 目标文件

目标文件交给链接器继续处理。普通接口需要三类信息：节、链接器可见符号，以及需要链接器修补的位置。

## COFF 目标文件

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

32 位相对调用使用 `coff_rel_i386_rel32`，64 位使用 `coff_rel_amd64_rel32`。

## ELF 目标文件

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

const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 8, elfobj_stt_func),
    format_elfobj_public("scratch", ".bss", bss_start, scratch, 64, elfobj_stt_object),
    format_elfobj_public("answer", ".rodata", data_start, answer, 4, elfobj_stt_object),
    format_elfobj_extern("puts", elfobj_stt_func)
)

const relocs: list = list.of(
    format_elfobj_reloc(".text", text_start, call_disp, "puts", elf_r_x86_64_plt32, 0xfffffffffffffffc)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
```

ELF32 使用 `format_elfobj32`。32 位相对调用常用 `elf_r_386_pc32`。

## API 摘要

| 格式 | API | 作用 |
| --- | --- | --- |
| COFF | `format_coff32(sections)` / `format_coff64(sections)` | 创建目标文件配置 |
| COFF | `format_coff_public(...)` | 定义公开符号 |
| COFF | `format_coff_extern(...)` | 声明外部符号 |
| COFF | `format_coff_reloc(...)` | 描述重定位字段 |
| COFF | `format_coff_tables_mut(plan, symbols, relocs)` | 附加符号和重定位集合 |
| ELF | `format_elfobj32(sections)` / `format_elfobj64(sections)` | 创建目标文件配置 |
| ELF | `format_elfobj_public(...)` | 定义公开符号及大小 |
| ELF | `format_elfobj_extern(...)` | 声明外部符号 |
| ELF | `format_elfobj_reloc(...)` | 描述带 addend 的重定位字段 |
| ELF | `format_elfobj_tables_mut(plan, symbols, relocs)` | 附加符号和重定位集合 |

先在代码中写入占位字段，再用 `format_*_reloc` 描述它。链接器会根据重定位记录修补这些字节。
