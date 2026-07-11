# 第 5 章：PE32 与 PE64 可执行文件

可移植可执行文件（PE）映像把 Windows 程序划分为多个命名节，并说明每个节如何保存在文件中、又如何映射到内存。常用格式接口根据一份已经声明的格式方案，构造 `DOS` 文件头、PE 标记、文件头、可选文件头、数据目录和节表。

本章构造普通的可执行文件映像。导入、动态链接库导出、资源、校验和以及完整的基址重定位流程将在后续章节介绍。

## 写入内容前选择位宽

32 位 x86 映像使用 `format_pe32`，64 位 x86 映像使用 `format_pe64`：

```text
format_pe32(options, sections)
format_pe64(options, sections)
```

两个构造函数使用相同的节描述项和格式构建流程。位宽会改变机器类型、可选文件头形式、默认映像基址、指针宽度，以及绝对地址字段采用的重定位类型。

`format_begin` 会选择对应的 x86 指令模式。即便如此，仍建议在源代码开头明确调用 `x86.use32()` 或 `x86.use64()`，以便在第一条指令出现前就说明预期的 x86 指令模式。命令行选择的目标平台也应与此一致。

| 映像 | 构造函数 | 命令行目标平台 | 默认映像基址 |
| --- | --- | --- | --- |
| 32 位 x86 | `format_pe32` | `x86` 或 `x86-32` | `0x00400000` |
| 64 位 x86 | `format_pe64` | `x86-64` | `0x0000000140000000` |

默认文件对齐为 512 字节，默认内存节对齐为 4096 字节。普通源代码只需声明各节的用途和权限，不应自行计算对齐后的相对虚拟地址或原始数据在文件中的位置。

## 选择映像角色、子系统和安全策略

PE 构造函数接收一个选项值，这个值由几组彼此独立的选择组合而成：

```text
映像角色       format_pe_exe
子系统         format_pe_console 或 format_pe_gui
内存策略       format_pe_nx
地址随机化策略 format_pe_aslr_auto
               format_pe_aslr_required
               format_pe_aslr_disabled
```

可执行文件方案必须恰好选择一种映像角色、一种子系统和一种地址空间布局随机化策略。未知选项或互相矛盾的选项会在开始生成输出内容前被拒绝。

普通可执行文件通常可以使用以下组合：

```text
format_pe_exe
    | format_pe_console
    | format_pe_nx
    | format_pe_aslr_auto
```

`format_pe_nx` 表示该映像支持数据页不可执行策略。每个节是否允许执行，仍由该节自身的权限决定。

子系统描述程序所处的 Windows 运行环境：

- `format_pe_console` 选择控制台子系统；
- `format_pe_gui` 选择图形界面子系统。

子系统选项不会生成运行库、创建窗口或添加导入项，它只记录加载器能够识别的子系统选择。图形界面程序仍需自行提供代码所需要的导入项和启动行为。

## 一个 PE64 控制台可执行文件

下面的映像把代码、只读数据、可变数据和预留空间分别放入不同的节：

```asm
// 导入常用格式接口，并明确选择 64 位 x86 指令模式。
import("format/format.inc");
x86.use64();

// 声明 PE64 控制台可执行文件，以及代码、数据和未初始化数据节。
const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".rdata",
            format_data | format_readable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data
                | format_readable
                | format_writeable
        )
    )
)
format_begin(image0);

// 在可执行代码节中定义返回 0 的程序入口。
format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

// 只读数据节保存不会在运行时修改的字符串。
format_section_begin(image0, ".rdata");
message:
    db("XIRASM PE64", 0);
format_section_end(image0, ".rdata");

// 可写数据节保存带有初始值的可变数据。
format_section_begin(image0, ".data");
counter:
    dd(1);
format_section_end(image0, ".data");

// 未初始化数据节只预留内存，不向文件写入 128 个零字节。
format_section_begin(image0, ".bss");
workspace:
    rb(128);
format_section_end(image0, ".bss");

// 绑定入口标号，并根据最终节布局完成文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

使用 x86-64 目标平台汇编：

```powershell
# 生成 64 位 Windows 可执行文件。
xirasm program.asm --target x86-64 -o program.exe
# 运行生成的程序，入口代码会返回 0。
.\program.exe
```

这个最小入口只返回 0。第 6 章会把它替换为对导入的 Windows 接口的显式调用。

## 按照节的用途理解格式方案

节列表就是文件映像的布局约定：

| 节 | 用途 | 权限 | 文件内容 |
| --- | --- | --- | --- |
| `.text` | 代码 | 读取、执行 | 指令 |
| `.rdata` | 已初始化数据 | 读取 | 常量字节 |
| `.data` | 已初始化数据 | 读取、写入 | 可变数据的初始值 |
| `.bss` | 未初始化数据 | 读取、写入 | 没有原始文件数据 |

常用格式接口会按照描述项的原有顺序，为每个描述项生成一个节表项。后续的 `format_section_begin` 和 `format_section_end` 调用会把内容写入对应名称的节。

`.bss` 会让文件映像的逻辑大小增加 128 字节，但不会在文件中增加 128 个零字节。它的节表项记录内存大小，而原始数据大小为零。如果后面还有文件中有实际字节的节，该节可以继续使用同一个文件位置，同时获得一个更靠后的、已经对齐的相对虚拟地址。

`message`、`counter` 和 `workspace` 都是普通的逻辑地址。虽然它们所在的节具有不同的文件位置和内存地址，后续指令、收尾处理、导出声明或重定位声明仍然可以使用这些标号。

## 定义入口后再进行绑定

创建最终格式方案之前，入口标号必须已经存在：

```text
const image: map = format_entry(image0, start)
format_finish(image)
```

`format_entry` 会返回更新后的格式方案。如果把 `image0` 传给 `format_finish`，入口绑定就会被丢弃；由于可执行文件映像必须具有入口点，完成格式时将会失败。

PE 文件头以相对虚拟地址保存入口位置。源代码只需传入逻辑标号，格式接口会根据所选映像基址和最终节布局推导相对虚拟地址。

## PE32 使用相同的构建流程

32 位形式只需改变构造函数、x86 指令模式和命令行目标平台，格式方案和节的构建流程保持不变：

```asm
// 导入常用格式接口，并明确选择 32 位 x86 指令模式。
import("format/format.inc");
x86.use32();

// 声明 PE32 控制台可执行文件，以及代码、数据和未初始化数据节。
const image0: map = format_pe32(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data
                | format_readable
                | format_writeable
        )
    )
)
format_begin(image0);

// 在代码节中定义返回 0 的 32 位程序入口。
format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

// 保存带有初始值的可变数据。
format_section_begin(image0, ".data");
counter:
    dd(1);
format_section_end(image0, ".data");

// 为运行时工作区预留内存，不增加相同大小的文件数据。
format_section_begin(image0, ".bss");
workspace:
    rb(64);
format_section_end(image0, ".bss");

// 绑定入口标号，并完成 32 位文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

使用 32 位 x86 目标平台汇编：

```powershell
# 生成 32 位 Windows 可执行文件。
xirasm program32.asm --target x86 -o program32.exe
# 运行生成的程序，入口代码会返回 0。
.\program32.exe
```

PE32 映像使用 32 位可选文件头和 `i386` 机器类型。PE64 映像使用 PE32+ 可选文件头和 `AMD64` 机器类型。

## 位宽改变地址字段，但不改变格式方案模型

源代码保存或重定位绝对地址时，两个位宽之间的差异最为明显：

| 项目 | PE32 | PE64 |
| --- | --- | --- |
| 绝对指针字段 | 32 位 | 64 位 |
| 常见数据声明 | `dd(0)` | `dq(0)` |
| 最终回填 | `store.u32` | `store.u64` |
| 基址重定位类型 | `HIGHLOW` | `DIR64` |
| 默认映像基址 | `0x00400000` | `0x0000000140000000` |
| 大地址感知标志 | 常用格式接口不使用 | 启用 |
| 高熵地址空间布局随机化标志 | 不适用 | 可重定位时启用 |

这些差异不需要两套不同的节管理代码。常用描述项、命名节调用、入口绑定和格式完成操作在两种位宽下完全相同。

不要把 64 位地址写入 PE32 数据字段，也不要为 PE64 指针使用 PE32 重定位类型。第 7 章会介绍完整的可重定位指针和动态链接库构建流程。

## 理解三种地址空间布局随机化策略

常用格式接口会让文件映像标志与源代码实际提供的重定位数据保持一致。

### 自动

只有当格式方案包含真正的 `format_fixups` 基址重定位节时，`format_pe_aslr_auto` 才会启用动态基址标志。没有基址重定位节时，文件映像仍然是有效的固定基址可执行文件，而不会错误地声称加载器能够安全地改变它的加载基址。

因此，`auto` 适合作为普通程序的默认选择：

```text
没有基址重定位节       固定基址映像
具有基址重定位节       可重定位映像
带基址重定位节的 PE64  动态基址与高熵虚拟地址
```

### 必须启用

如果格式方案中没有 `format_fixups` 节，`format_pe_aslr_required` 会拒绝该方案。当可重定位能力属于程序必须满足的约定时，应使用这个选项。

### 禁用

`format_pe_aslr_disabled` 不设置动态基址标志。文件映像有意固定在首选基址时，可以使用这个选项。

地址空间布局随机化选项不会自动发现绝对指针。源代码仍须声明每一个需要基址重定位的字段。

## 文件对齐与内存对齐彼此独立

PE 节使用两套位置坐标：

- 文件中的原始数据按照文件对齐值排列；
- 加载后的节相对虚拟地址按照内存节对齐值排列。

常用格式接口使用 512 字节文件对齐和 4096 字节内存节对齐。因此，小型可执行文件可以在文件中紧凑存放各节的实际数据，同时让加载后的每个节从按内存页对齐的相对虚拟地址开始。

未初始化数据区最能说明为什么必须区分这两套坐标。它可以占用内存，却不占用原始文件字节。格式接口根据最终节信息计算原始数据大小、虚拟大小、原始数据文件位置、相对虚拟地址、`SizeOfHeaders` 和 `SizeOfImage`。

普通源代码不应手工插入文件填充来模仿 PE 的内存节对齐。

## PE 可执行文件的常见错误

### 选项互相矛盾

同时选择 `EXE` 和 `DLL`、同时选择控制台和图形界面子系统，或者选择多种地址空间布局随机化策略，都会使 PE 格式方案失败。

### 缺少入口或丢弃入口绑定

可执行文件必须绑定入口标号，而且 `format_entry` 返回的更新后方案必须传递给 `format_finish`。

### 使用未声明的节名称

每个 `format_section_begin` 调用都必须引用原始方案中的一个描述项。任何节都不能打开两次，最终文件映像必须完成所有已经声明的节内容。

### 权限错误

代码通常需要读取和执行权限，不需要写入权限。可变数据和未初始化数据区通常需要读取和写入权限，不需要执行权限。

### 没有基址重定位节却声称可以重定位

可重定位能力可选时，使用 `format_pe_aslr_auto`。只有当格式方案包含重定位节，而且所有需要调整的绝对地址字段都具有重定位声明时，才应使用 `format_pe_aslr_required`。

## PE 可执行文件的实用规则

1. 普通的 64 位 Windows 程序使用 `format_pe64`。
2. 只有程序必须作为 32 位 x86 代码运行时，才使用 `format_pe32`。
3. 恰好选择一种子系统和一种地址空间布局随机化策略。
4. 普通应用程序启用 `format_pe_nx`。
5. 在 `format_begin` 之前声明完整的节列表。
6. 按照用途和权限分别存放代码、常量、可变数据和未初始化数据区。
7. 使用 `format_entry` 返回的格式方案绑定入口标号。
8. 让格式接口推导节表项、相对虚拟地址、原始数据文件位置和映像大小。
9. 除非文件映像需要更严格的策略，否则使用 `format_pe_aslr_auto`。
10. 通过各自的专用流程添加导入、重定位、资源和校验和，不要手工修改文件头。

第 6 章会在可执行文件方案中加入自动生成的导入表，并真正调用一个 Windows 接口。
