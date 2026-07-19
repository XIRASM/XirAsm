# 2. Windows PE 和 DLL

Windows 可执行文件和 DLL 都使用 PE。用 `format.inc` 生成 PE 时，配置里要写清文件角色、子系统、安全选项、ASLR 策略，以及文件包含哪些节。

## PE 选项

`format_pe32(options, sections)` 和 `format_pe64(options, sections)` 的 `options` 必须包含一个角色、一个子系统、一个 ASLR 策略；`format_pe_nx` 是可选安全标志。

| 分组 | 值 | 含义 |
| --- | --- | --- |
| 角色 | `format_pe_exe` | 可执行文件 |
| 角色 | `format_pe_dll` | DLL |
| 子系统 | `format_pe_console` | 控制台程序 |
| 子系统 | `format_pe_gui` | GUI 程序 |
| 安全 | `format_pe_nx` | 标记为 NX 兼容 |
| ASLR | `format_pe_aslr_auto` | 如果存在重定位节，就启用 ASLR |
| ASLR | `format_pe_aslr_required` | 要求启用 ASLR，并且必须声明重定位节 |
| ASLR | `format_pe_aslr_disabled` | 不启用 ASLR |

常见 PE 节：

| 节 | 推荐属性 |
| --- | --- |
| `".text"` | `format_code \| format_readable \| format_executable` |
| `".data"` | `format_data \| format_readable \| format_writeable` |
| `".bss"` | `format_uninitialized_data \| format_readable \| format_writeable` |
| `".idata"` | `format_imports \| format_readable \| format_writeable` |
| `".edata"` | `format_exports \| format_readable` |
| `".rsrc"` | `format_resources \| format_readable` |
| `".reloc"` | `format_fixups \| format_readable \| format_discardable` |

PE 节名最多 8 字节。导入、导出、资源和重定位这几类特殊节在同一配置里各只能出现一次。

## 最小 PE64 可执行文件

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
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

// BSS 只增加运行时内存大小，不写入初始化文件内容。
format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

`format_begin` 会写入并预留 PE 头和节表；`format_finish` 会在最终布局稳定后回填入口、节大小、RVA、文件偏移等字段。

## 导入 Windows API

导入表描述加载器需要填充的外部函数地址。先创建导入集合，再调用 `format_pe_import_section` 生成 `.idata`；不要自己打开 `.idata` 手写导入表项。

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
format_pe_import_many_mut(
    image,
    imports,
    "KERNEL32.DLL",
    list.of("ExitProcess", "GetCurrentProcessId")
)
format_pe_import_pairs_mut(
    image,
    imports,
    "ADVAPI32.DLL",
    list.of("close_registry_key", "RegCloseKey")
)

format_begin(image);

format_section_begin(image, ".text");
start:
    // Windows x64 调用需要 32 字节 shadow space；这里额外保持栈对齐。
    sub rsp, 40
    call [rel GetCurrentProcessId]
    xor ecx, ecx
    call [rel ExitProcess]
format_section_end(image, ".text");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);
```

导入相关函数：

| 函数 | 用途 |
| --- | --- |
| `format_pe_import_new()` | 创建空导入映射 |
| `format_pe_import_many_mut(plan, imports, dll, names)` | 从一个 DLL 批量加入同名导入 |
| `format_pe_import_pairs_mut(plan, imports, dll, pairs)` | 从一个 DLL 批量加入“本地槽名、真实 API 名”成对导入 |
| `format_pe_import_section(plan, name, imports)` | 生成已声明的 PE 导入节 |

同一个 `imports` 绑定可以多次传给 `format_pe_import_many_mut` 或 `format_pe_import_pairs_mut`，每次对应一个 DLL。PE64 通过导入槽调用时写 `call [rel slot_name]`；PE32 写 `call [slot_name]`。

## 导出 DLL 函数

DLL 导出把内部标签暴露成外部符号。`many` 使用标签原名导出，`pairs` 可以指定公开名称。

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
format_pe_export_many_mut(image, exports, list.of("x_add7", "x_sub3"))
format_pe_export_pairs_mut(image, exports, list.of("answer_impl", "x_answer"))

format_begin(image);

format_section_begin(image, ".text");
dll_main:
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

DLL 也需要入口标签。最小入口通常返回非零值，表示加载成功。

## 资源

资源节用于放已经编译好的 `.res` 资源树：

```text
// .rsrc 必须提前声明为 format_resources。
format_pe_resource_section(image, ".rsrc", "data/app.res");
```

`format_pe_resource_section(plan, name, path)` 会复制资源树并注册 PE 资源目录。不要在这次调用外面手动打开同一个 `.rsrc` 节。

## 基址重定位

基址重定位描述“文件里某个槽保存了绝对地址，加载器改变镜像基址时必须修正这个槽”。它不是普通的 `rel` 指令引用。

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
    sub rsp, 40
    mov rax, [rel worker_pointer]
    call rax
    mov ecx, eax
    call [rel ExitProcess]
worker:
    mov eax, 42
    ret
format_section_end(image, ".text");

format_section_begin(image, ".data");
worker_pointer:
    dq(0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs);

format_entry_mut(image, start)
format_finish(image);

defer {
    store.u64(worker_pointer, worker);
}
```

`format_pe_reloc_add_mut` 会根据 PE32/PE64 自动选择重定位类型。它的地址参数是“保存绝对地址的槽”，不是被指向的目标。PE32 用 `dd(0)` 和 `store.u32`，同一个函数会选择 32 位重定位。

## 校验和

如果需要 PE checksum，在 `format_finish(image)` 之后调用：

```text
format_finish(image);
format_pe_checksum(image);
```

校验和依赖最终文件字节，必须放在所有会改变文件内容的步骤之后。
