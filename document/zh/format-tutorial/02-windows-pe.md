# 2. Windows PE 和 DLL

Windows 上的可执行程序和 DLL 都用 PE 格式。用 `format.inc` 生成 PE 时，`options` 必须指定三项：文件角色是 exe 还是 DLL、用哪个子系统、ASLR 取哪种策略；`format_pe_nx` 另算一个可选标志。其余头部字段、节表、导入目录、导出目录和基址重定位表，都由 `format.inc` 从这几项推出来。

## PE 选项

`format_pe32(options, sections)` 和 `format_pe64(options, sections)` 的 `options` 必须指定一个角色、一个子系统、一个 ASLR 策略，`format_pe_nx` 可选。少给一组就报错：缺角色报 `PE format requires EXE or DLL`，缺子系统报 `PE format requires console or GUI subsystem`，缺 ASLR 报 `PE format requires an ASLR policy`。同一分组给两个值也报错，例如同时给出 console 和 gui，报 `PE format has multiple subsystems`。

| 分组   | 值                          | 含义                              |
| ------ | --------------------------- | --------------------------------- |
| 角色   | `format_pe_exe`           | 可执行文件                        |
| 角色   | `format_pe_dll`           | DLL                               |
| 子系统 | `format_pe_console`       | 控制台程序                        |
| 子系统 | `format_pe_gui`           | GUI 程序                          |
| 安全   | `format_pe_nx`            | 标记为 NX 兼容                    |
| ASLR   | `format_pe_aslr_auto`     | 存在重定位节时才启用 ASLR         |
| ASLR   | `format_pe_aslr_required` | 要求启用 ASLR，且必须声明重定位节 |
| ASLR   | `format_pe_aslr_disabled` | 不启用 ASLR                       |

`format_pe_nx` 写入 `DllCharacteristics` 的 `NX_COMPAT` 位。ASLR 三档写入同一字段的 `DYNAMIC_BASE` 位：

| 策略                                        | `DllCharacteristics`                                                    |
| ------------------------------------------- | -------------------------------------------------------------------------------- |
| `format_pe_aslr_auto`，未声明重定位节     | `DllCharacteristics = 0x100`，`DYNAMIC_BASE` 未置位，重定位目录为 `(0, 0)` |
| `format_pe_aslr_required`，已声明重定位节 | `DllCharacteristics = 0x160`，`DYNAMIC_BASE` 置位，重定位目录指向 `.reloc` |

未声明重定位节却要求 ASLR，报 `PE ASLR required needs a fixups section`。

`format_pe64` 生成 x86-64 映像，`format_pe64_arm64(options, sections)` 生成 AArch64 映像。两种机器共用容器布局、导入导出目录和 DIR64 基址重定位，差异只在文件头机器字段与指令编码。

常见 PE 节：

| 节           | 推荐属性                                                           |
| ------------ | ------------------------------------------------------------------ |
| `".text"`  | `format_code \| format_readable \| format_executable`              |
| `".data"`  | `format_data \| format_readable \| format_writeable`               |
| `".bss"`   | `format_uninitialized_data \| format_readable \| format_writeable` |
| `".idata"` | `format_imports \| format_readable \| format_writeable`            |
| `".edata"` | `format_exports \| format_readable`                               |
| `".rsrc"`  | `format_resources \| format_readable`                             |
| `".reloc"` | `format_fixups \| format_readable \| format_discardable`           |

PE 节名不得超过八字节。导入、导出、资源和重定位这四类特殊节在同一配置中各只能出现一次。

## 最小 PE64 可执行文件

```asm id=pe64-executable target=x86-64
import("format/format.inc")

// 可执行文件、控制台子系统，启用 DEP，不启用 ASLR。
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        // 代码节：可读可执行。
        format_section(".text", format_code | format_readable | format_executable),
        // BSS：只在内存中占 64 字节，不写入文件字节。
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    xor eax, eax
    ret
format_section_end(image, ".text")

format_section_begin(image, ".bss")
    rb(64)
format_section_end(image, ".bss")

// 入口地址不得为零：PE 配置未设置入口时，format_finish 报
// "PE executable or DLL requires an entry address"。
format_entry_mut(image, start)
format_finish(image)
```

`format_begin` 写入并预留 PE 头和节表；`format_finish` 在布局稳定后回填入口、节大小、RVA 和文件偏移。上例的结果是一个 1024 字节的 PE 映像：`Format: COFF-x86-64`、`Subsystem: IMAGE_SUBSYSTEM_WINDOWS_CUI`、`AddressOfEntryPoint: 0x1000`、`SizeOfHeaders: 512`、`SectionAlignment: 4096`、`FileAlignment: 512`。

## 导入 Windows API

导入表描述加载器在启动时要填的外部函数地址。顺序是：先声明 `.idata` 节，再建立导入集合，最后由 `format_pe_import_section` 生成表内容。**不要自行打开 `.idata` 手工填充导入表项**——描述符、查找表、地址表、提示名和 DLL 名字符串之间的 RVA 关系由 `format.inc` 推导。

```asm id=pe64-imports target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        // 导入节必须先声明，再交给 format_pe_import_section 生成内容。
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)

// 槽名默认取 API 原名；导入完成后可在指令中直接引用这些标号。
let imports: map = format_pe_import_new()
format_pe_import_many_mut(
    image,
    imports,
    "KERNEL32.DLL",
    list.of("ExitProcess", "GetCurrentProcessId")
)
// 同一个绑定可以继续加入其他 DLL；pairs 用于给 API 指定本地别名。
format_pe_import_pairs_mut(
    image,
    imports,
    "ADVAPI32.DLL",
    list.of("close_registry_key", "RegCloseKey")
)

format_begin(image)

format_section_begin(image, ".text")
start:
    // Windows x64 调用需要 32 字节 shadow space；此处额外占用 8 字节以保持 16 字节栈对齐。
    sub rsp, 40
    // PE64 通过 RIP 相对的导入槽调用。
    call [rel GetCurrentProcessId]
    xor ecx, ecx
    call [rel ExitProcess]
format_section_end(image, ".text")

// 在此生成 .idata：不要在该调用之外再次打开同一个节。
format_pe_import_section(image, ".idata", imports)

format_entry_mut(image, start)
format_finish(image)
```

生成的映像为 1536 字节，导入目录里有两张表：`KERNEL32.DLL` 带 `ExitProcess` 和 `GetCurrentProcessId`，`ADVAPI32.DLL` 带 `RegCloseKey`。第二张表里没有 `close_registry_key`——`pairs` 的写法是「本地槽名, 真实 API 名」，本地名只用于源码中引用。

导入相关函数：

| 函数                                                      | 参数                              | 用途                               |
| --------------------------------------------------------- | --------------------------------- | ---------------------------------- |
| `format_pe_import_new()`                                | 无                                | 建立空导入集合                     |
| `format_pe_import_many_mut(plan, imports, dll, names)`  | 配置、集合、DLL 名、函数名列表    | 按原名批量加入，槽名与函数名相同   |
| `format_pe_import_pairs_mut(plan, imports, dll, pairs)` | 配置、集合、DLL 名、槽名/函数名对 | 批量加入，并为每个函数指定本地槽名 |
| `format_pe_import_section(plan, name, imports)`         | 配置、已声明的导入节名、集合      | 生成导入节内容并注册导入目录       |

`pairs` 列表的项数必须为偶数，超过 128 项报 `PE64 import pairs exceed the batch limit`；项数为奇数报 `PE64 import pairs require slot/name entries`。同一个槽名不能指向两个不同的函数，冲突时报 `PE import slot already maps to a different name`。

PE64 通过导入槽调用时写成 `call [rel slot_name]`，PE32 写成 `call [slot_name]`——64 位下导入槽地址是 RIP 相对的，32 位下是绝对地址。

## 导出 DLL 函数

DLL 导出把内部标签暴露为外部符号。`many` 按标签原名导出，`pairs` 指定公开名称。

```asm id=pe64-dll-exports target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    // 角色改为 format_pe_dll，文件头会置 IMAGE_FILE_DLL 位。
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".edata", format_exports | format_readable)
    )
)

let exports: list = format_pe_export_new()
// 两个标签按原名导出。
format_pe_export_many_mut(image, exports, list.of("x_add7", "x_sub3"))
// answer_impl 以 x_answer 之名导出。
format_pe_export_pairs_mut(image, exports, list.of("answer_impl", "x_answer"))

format_begin(image)

format_section_begin(image, ".text")
dll_main:
    // DLL 入口返回非零值表示加载成功。
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
format_section_end(image, ".text")

// 最后一个参数是 DLL 自身的名字，写入导出目录。
format_pe_export_section(image, ".edata", exports, "xirasm_demo.dll")

format_entry_mut(image, dll_main)
format_finish(image)
```

生成的映像为 1536 字节，导出表里有三个导出，序数从 1 开始，名字按字典序排列（`x_add7`、`x_answer`、`x_sub3`）——PE 的名字指针表要求有序，`format.inc` 会自动排序。导出表为空报 `PE export table requires at least one export`，DLL 名字为空报 `PE export DLL name is empty`。`pairs` 列表的项数同样必须为偶数，上限 128。

## 资源

资源节存放编译好的 `.res` 资源树——它是 `rc.exe` 或 `windres` 的产物，不是手写的文本文件。先声明 `.rsrc` 为 `format_resources`，再把文件路径交给生成函数：

```asm id=pe64-resources target=x86-64
import("format/format.inc")

// 带资源节的 PE：.res 是 rc.exe / windres 编译出来的资源树。
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        // .rsrc 必须声明为 format_resources。
        format_section(".rsrc", format_resources | format_readable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    ret
format_section_end(image, ".text")

// 复制资源树并注册资源目录；不要在这个调用之外再打开 .rsrc。
format_pe_resource_section(image, ".rsrc", "app.res")
format_entry_mut(image, start)
format_finish(image)
```

生成的映像为 1536 字节：`.rsrc` 节占 364 字节，可选头的资源目录槽（第 3 项数据目录）填成 `RVA = 0x2000`、`size = 364`。

`format_pe_resource_section(plan, name, path)` 按**类型 / 名称 / 语言**三级重排资源树，各级目录、名称字符串和偏移由 `format.inc` 生成，`.res` 里原有的记录顺序不影响结果。`.res` 里没有非空记录时报 `compiled PE resource file contains no non-empty records`。

`path` 的相对路径基准是**读这个文件的代码所在目录**，而读 `.res` 的代码在 `include/format/pe_resource.inc` 里，所以相对路径的基准是 `include/format/`，既不是源文件所在目录，也不是当前工作目录。要找源文件旁边的 `.res`，把路径写成绝对路径，否则会报 `the file this statement reads cannot be opened (FileNotAvailable)`。

## 基址重定位

基址重定位描述的是「文件内某个槽保存了绝对地址，加载器更换基址时必须修正它」。它与 `rel` 指令引用是两回事：`rel` 引用本身就是相对地址，加载器无需处理；只有写入内存的绝对地址才需要重定位记录。

```asm id=pe64-relocations target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    // 要求 ASLR，因此必须声明重定位节。
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

format_begin(image)

format_section_begin(image, ".text")
start:
    // Windows x64 调用前先留出 shadow space。
    sub rsp, 40
    // 从 .data 中取出函数地址再调用。
    mov rax, [rel worker_pointer]
    call rax
    mov ecx, eax
    call [rel ExitProcess]
worker:
    mov eax, 42
    ret
format_section_end(image, ".text")

format_section_begin(image, ".data")
// 该槽保存绝对地址，加载器更换基址时必须修正它。
worker_pointer:
    dq(0)
format_section_end(image, ".data")

format_pe_import_section(image, ".idata", imports)

// 记录的是「槽本身」的地址，不是它指向的 worker。
let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs)

format_entry_mut(image, start)
format_finish(image)

// 绝对地址必须等全部标签地址稳定后再回填。
defer {
    store.u64(worker_pointer, worker)
}
```

生成的映像为 3072 字节。重定位目录指向 `.reloc`，其中是一个基址重定位块：页 RVA 为 `0x2000`，块大小为 12（8 字节块头，加一条 2 字节记录，再加 2 字节终止项），记录类型为 10，即 `IMAGE_REL_BASED_DIR64`，偏移为 0，合起来指向 `worker_pointer`。`DYNAMIC_BASE` 同时置位，符合 `format_pe_aslr_required` 的要求。

`format_pe_reloc_add_mut` 依据配置中的位宽自动选择 32 位或 64 位重定位类型，不需要手工填写类型码。记录必须按 RVA 升序传给 `format_pe_reloc_section`。PE32 用 `dd(0)` 保存槽、用 `store.u32` 回填，同一个函数会自动选择 32 位类型。

| 函数                                               | 参数                                 | 用途                           |
| -------------------------------------------------- | ------------------------------------ | ------------------------------ |
| `pe_reloc_new()`                                 | 无                                   | 建立空重定位列表               |
| `format_pe_reloc_add_mut(plan, relocs, storage)` | 配置、列表、保存绝对地址的槽地址     | 追加一条按位宽选择的重定位记录 |
| `format_pe_reloc_section(plan, name, relocs)`    | 配置、已声明的重定位节名、已排序列表 | 生成重定位节并注册重定位目录   |

### 观察加载器的修正过程

可执行文件通常看不出重定位有没有生效：加载器按链接时写入的 `ImageBase` 映射，就走不到修正那一步。要观察它，把同样结构写成 DLL，让宿主读回某个绝对指针：

```asm id=pe64-reloc-probe target=x86-64
import("format/format.inc")

// 把函数地址存进 .data，再由导出函数读回，用来验证加载器是否修正了它。
let image: map = format_pe64(
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".edata", format_exports | format_readable),
        // format_pe_aslr_required 要求必须声明重定位节。
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)

format_begin(image)

format_section_begin(image, ".text")
dll_main:
    // DLL 入口返回非零值表示加载成功。
    mov eax, 1
    ret
worker:
    // 返回固定值，用来证明指针确实指向它。
    mov eax, 42
    ret
read_pointer:
    // 把槽里存着的 worker 地址读回来交给宿主。
    mov rax, [rel worker_pointer]
    ret
format_section_end(image, ".text")

// 槽里写的是 worker 的绝对地址，换基址时必须修正。
format_section_begin(image, ".data")
worker_pointer:
    dq(0)
format_section_end(image, ".data")

let exports: list = format_pe_export_new()
format_pe_export_many_mut(image, exports, list.of("read_pointer"))
format_pe_export_section(image, ".edata", exports, "reloc_probe.dll")

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs)

format_entry_mut(image, dll_main)
format_finish(image)

// 绝对地址要等标签地址稳定后再回填。
defer {
    store.u64(worker_pointer, worker)
}
```

宿主加载它，取回槽里的地址，再调用该地址：

```c
#include <windows.h>
#include <stdio.h>

int main(void) {
    HMODULE dll = LoadLibraryA("reloc_probe.dll");
    if (!dll) { printf("load failed: %lu\n", GetLastError()); return 2; }

    /* 取回槽里的地址并调用它：只有加载器改过这个槽，调用才会成功。 */
    int (*read_pointer)(void) = (int (*)(void))GetProcAddress(dll, "read_pointer");
    long long stored = (long long)read_pointer();
    printf("DLL loaded at : %p\n", (void *)dll);
    printf("stored pointer: 0x%llX\n", stored);
    printf("worker() = %d\n", ((int (*)(void))stored)());
    return 0;
}
```

编译时把 DLL 与宿主放在同一目录，运行结果形如：

```text
DLL loaded at : 00007FFB4E3E0000
stored pointer: 0x7FFB4E3E1006
worker() = 42
```

加载地址不是链接时写入的 `0x140000000`，说明映像被搬到了别处；而槽里读回的地址落在加载地址范围内，调用它还能返回 42，说明**加载器按 `.reloc` 修正了这个绝对地址**。如果记录写错位置，读回的会是链接时的旧地址，调用它就会崩溃。

## 校验和

PE 的 `CheckSum` 字段覆盖整个文件，因此只能在文件字节定型之后计算：

```asm id=pe64-checksum target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    xor eax, eax
    ret
format_section_end(image, ".text")

format_entry_mut(image, start)
format_finish(image)

// 校验和依赖最终文件字节，因此放在最后一步。
format_pe_checksum(image)
```

`format_pe_checksum` 从第一个节的开头度量到最后一个节的结尾，因此调用前至少要有一个节，否则报 `PE checksum requires at least one section`。上例的文件是 1024 字节，`CheckSum` 字段为 `0x4A36`。
