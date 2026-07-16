# 3. Linux ELF 可执行文件和共享库

普通接口用命名加载段描述 ELF 镜像。文件位置、虚拟地址、文件大小、内存大小和权限由格式配置推导。

## ELF 可执行文件

固定地址可执行文件使用 `format_elf_exec`：

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

ELF32 使用 `format_elf32(format_elf_exec, segments)`。

## ELF64 PIE

位置无关可执行文件使用 `format_elf_pie`：

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    // 加载器改变 PIE 基址后，这两个标签引用仍然有效。
    lea rbx, [rel scratch]
    lea rsi, [rel message]
    mov dword [rbx], 0x5a
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text");

format_segment_begin(image, ".bss");
scratch:
    rb(64);
format_segment_end(image, ".bss");

format_segment_begin(image, ".rodata");
message:
    db("XIRASM PIE", 0);
format_segment_end(image, ".rodata");

format_entry_mut(image, start)
format_finish(image);
```

文件格式是位置无关的，指令也必须遵守目标 ISA 的位置无关规则。x86-64 访问本镜像内标签时使用 `rel`，它编码相对位移，不需要绝对动态重定位。PIE 或共享库中保存的绝对指针需要动态重定位；普通接口不提供任意用户指针重定位，这类需求属于直接 ELF 层。普通接口暂不提供 ELF32 PIE。

## ELF64 可执行文件导入

当前普通接口为固定地址 ELF64 可执行文件生成 PLT/GOT 动态导入。PIE 不使用这条导入流程。

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

let imports: list = format_elfexe_import_new()
// 同一个库一次加入多个 API。
format_elfexe_import_many_mut(imports, "libc.so.6", list.of("getpid", "getppid"))
// 再加入另一个库，并把 cos 的本地前缀改成 cos_fn。
format_elfexe_import_pairs_mut(imports, "libm.so.6", list.of("cos_fn", "cos"))
format_elfexe_tables_mut(image, imports)
format_begin(image);

format_segment_begin(image, ".text");
start:
    call getpid_plt
    call getppid_plt
    xor edi, edi
    mov eax, 60
    syscall
format_segment_end(image, ".text");

format_entry_mut(image, start)
format_finish(image);
```

每个库调用一次批量接口，并持续更新同一个 `imports`。`format_elfexe_import_many_mut` 会为同名导入生成 `<name>_gotplt` 和 `<name>_plt`；别名导入 `cos_fn` 对应 `cos_fn_gotplt` 和 `cos_fn_plt`。

## ELF64 共享库

共享库没有普通可执行入口。它通过动态符号表导出符号，也可以声明导入。

```asm
import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_demo.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

let exports: list = format_elfso_export_new()
// 两个四字节函数直接使用标签名导出。
format_elfso_export_many_mut(exports, list.of("x_add7", "x_sub3"), ".text", 4)
// answer_impl 对外使用 x_answer。
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

format_finish(image);
```

## ELF64 共享库导入

共享库也可以把多个库的导入收集到同一个列表：

```asm
import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_report.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)

let exports: list = format_elfso_export_new()
format_elfso_export_pairs_mut(exports, list.of("report_impl", "x_report"), ".text", 18)

let imports: list = format_elfso_import_new()
// libc 中的两个 API 使用同名本地标签。
format_elfso_import_many_mut(imports, "libc.so.6", list.of("puts", "getpid"))
// 第二个库把 cos 映射到本地前缀 cos_fn。
format_elfso_import_pairs_mut(imports, "libm.so.6", list.of("cos_fn", "cos"))
format_elfso_tables_mut(image, exports, imports)

format_begin(image);

format_segment_begin(image, ".text");
report_impl:
    lea rdi, [rel message]
    call puts_plt
    call getpid_plt
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
message:
    db("XIRASM shared object", 0);
format_segment_end(image, ".data");

format_finish(image);
```

即使示例没有调用 `cos_fn_plt`，该标签和 `cos_fn_gotplt` 仍会生成。本镜像内的数据使用 `rel` 引用，外部函数则通过生成的 PLT 标签调用。

## API 摘要

| API | 作用 |
| --- | --- |
| `format_elf32(format_elf_exec, segments)` | ELF32 可执行文件 |
| `format_elf64(format_elf_exec, segments)` | ELF64 固定地址可执行文件 |
| `format_elf64(format_elf_pie, segments)` | ELF64 PIE |
| `format_elf64_so(soname, segments)` | ELF64 共享库 |
| `format_elfexe_import_new()` | 创建可执行文件导入集合 |
| `format_elfexe_import_many_mut(imports, library, names)` | 批量添加同名 PLT/GOT 导入 |
| `format_elfexe_import_pairs_mut(imports, library, pairs)` | 批量映射本地名称和导入名 |
| `format_elfexe_tables_mut(plan, imports)` | 把导入集合附加到可执行文件配置 |
| `format_elfso_export_new()` | 创建共享库导出集合 |
| `format_elfso_export_many_mut(exports, names, segment, size)` | 批量导出同名标签 |
| `format_elfso_export_pairs_mut(exports, pairs, segment, size)` | 批量映射目标标签和公开名称 |
| `format_elfso_import_new()` | 创建共享库导入集合 |
| `format_elfso_import_many_mut(imports, library, names)` | 批量添加共享库导入 |
| `format_elfso_import_pairs_mut(imports, library, pairs)` | 批量映射本地名称和导入名 |
| `format_elfso_tables_mut(plan, exports, imports)` | 附加共享库动态符号信息 |
