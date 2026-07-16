# 2. Windows PE 和 DLL

PE 配置需要指定文件角色、子系统、内存保护策略、地址随机化策略和节列表。

## PE 选项

`format_pe32(options, sections)` 和 `format_pe64(options, sections)` 必须各选一个文件角色、子系统和 ASLR 策略。`format_pe_nx` 可以按需加入。

| 分组 | 选项 | 作用 |
| --- | --- | --- |
| 文件角色 | `format_pe_exe` | 可执行文件 |
| 文件角色 | `format_pe_dll` | DLL |
| 子系统 | `format_pe_console` | 控制台程序 |
| 子系统 | `format_pe_gui` | 图形界面程序 |
| 内存保护 | `format_pe_nx` | 标记镜像兼容不可执行数据页 |
| ASLR | `format_pe_aslr_auto` | 存在重定位数据时启用 ASLR |
| ASLR | `format_pe_aslr_required` | 必须提供重定位数据并启用 ASLR |
| ASLR | `format_pe_aslr_disabled` | 禁用 ASLR |

常用节：

| 节名 | 属性 |
| --- | --- |
| `".text"` | `format_code \| format_readable \| format_executable` |
| `".data"` | `format_data \| format_readable \| format_writeable` |
| `".bss"` | `format_uninitialized_data \| format_readable \| format_writeable` |
| `".idata"` | `format_imports \| format_readable \| format_writeable` |
| `".edata"` | `format_exports \| format_readable` |
| `".rsrc"` | `format_resources \| format_readable` |
| `".reloc"` | `format_fixups \| format_readable \| format_discardable` |

## 最小 PE64 可执行文件

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
start:
    xor eax, eax
    ret
format_section_end(image, ".text");

format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

## 导入 Windows API

先创建导入集合，再按 DLL 成组添加 API。`format_pe_import_pairs_mut` 的 `pairs` 参数按“本地槽名、导入名”重复排列。

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)

let imports: map = format_pe_import_new()
// 同名批量接口一次加入同一个 DLL 的多个 API。
format_pe_import_many_mut(
    image,
    imports,
    "KERNEL32.DLL",
    list.of("ExitProcess", "GetCurrentProcessId")
)
// 再次调用即可加入另一个 DLL；pairs 还能指定本地槽名。
format_pe_import_pairs_mut(
    image,
    imports,
    "ADVAPI32.DLL",
    list.of("close_registry_key", "RegCloseKey")
)
format_begin(image);

format_section_begin(image, ".text");
start:
    sub rsp, 40
    call [rel GetCurrentProcessId]
    xor ecx, ecx
    call [rel ExitProcess]
format_section_end(image, ".text");

format_pe_import_section(image, ".idata", imports);
format_entry_mut(image, start)
format_finish(image);
```

| API | 参数 | 作用 |
| --- | --- | --- |
| `format_pe_import_new()` | 无 | 创建空导入集合 |
| `format_pe_import_many_mut(plan, imports, dll, names)` | 配置、导入集合、DLL、名称列表 | API 名与本地槽名相同 |
| `format_pe_import_pairs_mut(plan, imports, dll, pairs)` | 配置、导入集合、DLL、槽名/导入名列表 | 自定义本地槽名 |
| `format_pe_import_section(plan, name, imports)` | 配置、导入节名、导入集合 | 生成 `.idata` |

每个 DLL 调用一次批量接口，并持续更新同一个 `imports`，最终生成的 `.idata` 就会包含全部 DLL 和 API。PE64 通过 `call [rel slot_name]` 调用导入函数；PE32 使用 `call [slot_name]`。

## 导出 DLL 函数

`format_pe_export_many_mut` 批量导出同名标签；`format_pe_export_pairs_mut` 的 `pairs` 参数按“目标标签、公开名称”重复排列。

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".edata", format_exports | format_readable)
    )
)

let exports: list = format_pe_export_new()
// 两个标签直接使用原名导出。
format_pe_export_many_mut(image, exports, list.of("x_add7", "x_sub3"))
// answer_impl 对外使用 x_answer 这个名称。
format_pe_export_pairs_mut(image, exports, list.of("answer_impl", "x_answer"))
format_begin(image);

format_section_begin(image, ".text");
dll_main:
    // 最小 DLL 入口返回 TRUE。
    mov eax, 1
    ret
x_add7:
    lea eax, [ecx + 7]
    ret
x_sub3:
    lea eax, [ecx - 3]
    ret
answer_impl:
    mov eax, 42
    ret
format_section_end(image, ".text");

format_pe_export_section(image, ".edata", exports, "xirasm_demo.dll");
format_entry_mut(image, dll_main)
format_finish(image);
```

| API | 作用 |
| --- | --- |
| `format_pe_export_new()` | 创建空导出集合 |
| `format_pe_export_many_mut(plan, exports, names)` | 批量导出同名标签 |
| `format_pe_export_pairs_mut(plan, exports, pairs)` | 批量映射目标标签和公开名称 |
| `format_pe_export_section(plan, name, exports, dll_name)` | 生成 `.edata` |

## 资源

先把 `.rsrc` 声明为 `format_resources`，再把编译好的 `.res` 文件交给封装：

```text
format_pe_resource_section(image, ".rsrc", "data/app.res");
```

| API | 参数 | 作用 |
| --- | --- | --- |
| `format_pe_resource_section(plan, name, path)` | 配置、已声明的资源节名、`.res` 路径 | 写入编译后的资源树并登记 PE 资源目录 |

## 基址重定位

写入绝对地址和声明基址重定位是两件事。下面是可直接汇编的 PE64 模板：

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
let imports: map = format_pe_import_new()
format_pe_import_many_mut(image, imports, "KERNEL32.DLL", list.of("ExitProcess"))
format_begin(image);

format_section_begin(image, ".text");
start:
    // 为两次 Windows x64 调用预留 shadow space 并对齐栈。
    sub rsp, 40
    // 指令通过相对地址访问指针槽。
    mov rax, [rel worker_pointer]
    call rax
    // 用 ExitProcess 明确结束示例程序。
    mov ecx, eax
    call [rel ExitProcess]
worker:
    mov eax, 42
    ret
format_section_end(image, ".text");

format_section_begin(image, ".data");
worker_pointer:
    // 文件中保存的是绝对指针，因此这个槽需要基址重定位。
    dq(0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs);

format_entry_mut(image, start)
format_finish(image);

// 标签地址稳定后再写入最终绝对值。
defer {
    store.u64(worker_pointer, worker);
}
```

`format_pe_reloc_add_mut` 的地址参数是“保存指针的槽”，不是指针指向的目标。它会根据 PE32 或 PE64 选择重定位类型，记录必须按 RVA 升序传给 `format_pe_reloc_section`。`rel` 指令引用本身是相对位移，不需要基址重定位。PE32 对应使用 `dd(0)` 和 `store.u32`。

| API | 参数 | 作用 |
| --- | --- | --- |
| `pe_reloc_new()` | 无 | 创建空重定位列表 |
| `format_pe_reloc_add_mut(plan, relocs, storage)` | 配置、列表、指针存储地址 | 添加与 PE 位宽匹配的基址重定位 |
| `format_pe_reloc_section(plan, name, relocs)` | 配置、已声明的重定位节名、已排序列表 | 生成 `.reloc` 并登记数据目录 |

## 校验和

校验和依赖最终文件内容，因此在 `format_finish` 之后调用：

```text
format_pe_checksum(image);
```

`format_pe_checksum(plan)` 接收已经完成的 PE 配置，并根据最终文件内容回填校验和字段。
