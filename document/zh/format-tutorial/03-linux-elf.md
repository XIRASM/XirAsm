# 3. Linux ELF 可执行文件和共享库

ELF 可执行文件和共享库按“装载段”描述运行时映射。一个装载段包含文件偏移、虚拟地址、文件大小、内存大小和权限。`format.inc` 会根据 `format_segment(...)` 生成程序头并处理对齐。

## ELF 可执行文件

`format_elf32(format_elf_exec, segments)` 生成 ELF32 固定地址可执行文件。`format_elf64(format_elf_exec, segments)` 生成 ELF64 固定地址可执行文件。

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable),
        format_segment(".bss", format_load | format_readable | format_writeable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
answer:
    dd(42);
format_segment_end(image, ".data");

format_segment_begin(image, ".bss");
scratch:
    rb(128);
format_segment_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

BSS 段只增加内存大小，不增加初始化文件内容。`format.inc` 会让程序头里的 `filesz` 和 `memsz` 表达这个差异。

## ELF64 PIE

PIE 使用 `format_elf64(format_elf_pie, segments)`。`format.inc` 目前只支持 ELF64 PIE；ELF32 PIE 需要走更专门的格式构造路线。

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    xor eax, eax
    ret
format_segment_end(image, ".text");

format_entry_mut(image, start)
format_finish(image);
```

ELF 可执行文件导入目前只支持 ELF64 固定地址 `format_elf_exec`。不要把 `format_elfexe_tables_mut` 挂到 PIE 配置上。

## ELF64 可执行文件导入

ELF64 固定地址可执行文件可以通过 `format.inc` 生成 PLT、GOT、动态段和相关重定位。导入集合是 `list`，可以按库名分组追加。

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

let imports: list = format_elfexe_import_new()
format_elfexe_import_many_mut(imports, "libc.so.6", list.of("getpid"))
format_elfexe_import_pairs_mut(imports, "libm.so.6", list.of("cos_fn", "cos"))
format_elfexe_tables_mut(image, imports)

format_begin(image);

format_segment_begin(image, ".text");
start:
    call getpid_plt
    xor edi, edi
    mov eax, 60
    syscall
format_segment_end(image, ".text");

format_entry_mut(image, start)
format_finish(image);
```

`many` 会用导入名生成本地标签，例如 `getpid_plt` 和 `getpid_gotplt`。`pairs` 的列表按“本地前缀、真实符号名”成对出现，例如上面的 `cos_fn` 会生成 `cos_fn_plt` 和 `cos_fn_gotplt`。

## ELF64 共享库

共享库不使用普通可执行入口。它需要 SONAME、装载段，以及至少一个导出符号。导入是可选的。

```asm
import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_demo.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)

let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("x_add7", "x_sub3"), ".text", 4)
format_elfso_export_pairs_mut(exports, list.of("answer_impl", "x_answer"), ".text", 6)
format_elfso_tables_mut(image, exports, list.new())

format_begin(image);

format_segment_begin(image, ".text");
x_add7:
    lea eax, [rdi + 7]
    ret
x_sub3:
    lea eax, [rdi - 3]
    ret
answer_impl:
    mov eax, 42
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
export_data:
    dq(0x1122334455667788);
format_segment_end(image, ".data");

format_finish(image);
```

导出函数需要说明所在装载段和符号大小。`format.inc` 会生成动态符号、字符串表、hash、dynamic、GOT/PLT 等必要元数据。

## ELF64 共享库导入

共享库也可以声明导入：

```text
let imports: list = format_elfso_import_new()
format_elfso_import_many_mut(imports, "libc.so.6", list.of("puts", "getpid"))
format_elfso_import_pairs_mut(imports, "libm.so.6", list.of("cos_fn", "cos"))
format_elfso_tables_mut(image, exports, imports)
```

导入名不能和导出名冲突；生成的 `*_plt` 和 `*_gotplt` 标签也必须唯一。内部数据引用通常写 `rel`，导入调用使用生成的 PLT 标签。

## 选择目标机器

`format_elf64` 和 `format_elf64_so` 默认生成 x86-64 映像。AArch64 有对应的入口，机器来自配置时可以用带机器的通用形式：

| 入口 | 产物 |
| --- | --- |
| `format_elf64(options, segments)` | ELF64 x86-64 固定地址可执行文件或 PIE |
| `format_elf64_aarch64(options, segments)` | ELF64 AArch64 固定地址可执行文件或 PIE |
| `format_elf64_machine(options, segments, machine)` | 用 `elf_machine_x86_64` 或 `elf_machine_aarch64` 指定机器 |
| `format_elf64_so(soname, segments)` | ELF64 x86-64 共享库，LOAD 段按 4 KiB 对齐 |
| `format_elf64_so_aarch64(soname, segments)` | ELF64 AArch64 共享库，LOAD 段按 16 KiB 对齐 |
| `format_elfobj64_aarch64(sections)` | AArch64 ELF64 目标文件 |

两种机器有两处差别。AArch64 把 LOAD 段对齐到 16 KiB，这是 Android 15 及以后设备要求的页大小，可执行文件、PIE 和共享库都适用；x86-64 保持 Linux 默认的 4 KiB。导入机制也不同：x86-64 走 PLT 条目调用，AArch64 走 GLOB_DAT 槽位（`format_elfso_import_slots_mut`），因此可执行文件的导入路径只支持 x86-64——AArch64 应用改用共享库导入。

更大的页对齐只在段需要挪到下一个页边界时多花文件空间：虚拟地址按整页前进，文件布局仍然紧凑。要换别的页大小，可以在 `format_begin` 之前给计划设置 `"load_align"`。

## ELF API 摘要

| 函数 | 用途 |
| --- | --- |
| `format_elf32(format_elf_exec, segments)` | ELF32 固定地址可执行文件 |
| `format_elf64(format_elf_exec, segments)` | ELF64 x86-64 固定地址可执行文件 |
| `format_elf64(format_elf_pie, segments)` | ELF64 x86-64 PIE |
| `format_elf64_aarch64(options, segments)` | ELF64 AArch64 固定地址可执行文件或 PIE |
| `format_elf64_machine(options, segments, machine)` | 指定机器的 ELF64 可执行文件或 PIE |
| `format_elf64_so(soname, segments)` | ELF64 x86-64 共享库 |
| `format_elf64_so_aarch64(soname, segments)` | ELF64 AArch64 共享库，按安卓页大小对齐 |
| `format_elf64_so_machine(soname, segments, machine)` | 指定机器的 ELF64 共享库 |
| `format_elfobj64_aarch64(sections)` | AArch64 ELF64 目标文件 |
| `format_elfexe_import_new()` | 创建 ELF64 可执行文件导入列表 |
| `format_elfexe_import_many_mut(imports, library, names)` | 从同一个库批量加入同名导入 |
| `format_elfexe_import_pairs_mut(imports, library, pairs)` | 加入“本地前缀、真实符号名”成对导入 |
| `format_elfexe_tables_mut(plan, imports)` | 把可执行文件导入元数据挂到配置上 |
| `format_elfso_export_new()` | 创建共享库导出列表 |
| `format_elfso_export_many_mut(exports, names, segment, size)` | 批量导出同名符号 |
| `format_elfso_export_pairs_mut(exports, pairs, segment, size)` | 批量导出“内部标签、公开名称”成对符号 |
| `format_elfso_import_new()` | 创建共享库导入列表 |
| `format_elfso_import_many_mut(imports, library, names)` | 从同一个库批量加入共享库导入 |
| `format_elfso_import_pairs_mut(imports, library, pairs)` | 加入共享库“本地前缀、真实符号名”成对导入 |
| `format_elfso_import_slots_mut(imports, library, names)` | AArch64 共享库 GLOB_DAT 导入槽位 |
| `format_elfso_tables_mut(plan, exports, imports)` | 把共享库动态元数据挂到配置上 |
