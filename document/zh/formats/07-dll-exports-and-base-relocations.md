# 第 7 章：`DLL` 导出与基址重定位

动态链接库（`DLL`）是一种 PE 文件映像，由其他进程加载到自己的地址空间中。`DLL` 可以导出函数、数据，或者同时导出两者。`DLL` 入口是供加载器调用的初始化代码，与外部调用方按名称查找的导出符号相互独立。

常用格式接口对 `DLL` 使用与可执行文件相同的 PE32 和 PE64 节构建流程，主要区别如下：

- 选择 `format_pe_dll`，而不是 `format_pe_exe`；
- 提供导出列表和用途为 `format_exports` 的节；
- 为改用其他映像基址后仍须有效的绝对地址字段提供基址重定位；
- 编写适合 `DLL` 加载过程调用的入口例程。

## `DLL` 入口不是导出

Windows 在加载或卸载模块时可能调用 `DLL` 入口。入口接收平台规定的参数，并返回布尔结果。下面这个最小入口接受所有通知：

```text
dll_entry:
    mov eax, 1
    ret
```

入口标号仍通过 `format_entry` 绑定。导出函数需要单独声明，也可以使用完全不同的标号。

`DLL` 入口应当只完成少量工作。复杂初始化、调用导入函数、加锁、创建线程以及调用方专用的设置，更适合放在由程序明确调用的导出函数中。

## 构建导出列表

导出项保存在不可变列表中：

```text
const exports0: list = pe_export_new()
const exports1: list = pe_export_use64(
    exports0,
    "answer_value",
    "xir_answer_value"
)
const exports: list = pe_export_use64(
    exports1,
    "answer",
    "xir_answer"
)
```

每项声明连接两部分信息：

```text
目标标号         DLL 内部的地址
导出名称         外部调用方能够查找的名称
```

PE32 使用 `pe_export_use32`，PE64 使用 `pe_export_use64`。函数导出和数据导出采用相同的声明方式，因为导出表项记录的是相对虚拟地址，而不是源语言中的值类型。

格式接口在创建 PE 名称指针表时会对导出名称排序。源代码可以按照最能表达程序结构的顺序声明导出项，不需要自行遵循表中的名称排序规则。

## 可重设基址的 PE64 `DLL`

下面的 `DLL` 导出名为 `xir_answer` 的函数和名为 `xir_answer_value` 的整数。函数会读取文件映像内部保存的绝对指针，因此该指针需要一项基址重定位：

```asm
// 导入常用格式接口，并选择 64 位 x86 指令模式。
import("format/format.inc");
x86.use64();

// 将数据标号和函数标号分别登记为外部可见的导出名称。
const exports0: list = pe_export_new()
const exports1: list = pe_export_use64(
    exports0,
    "answer_value",
    "xir_answer_value"
)
const exports: list = pe_export_use64(
    exports1,
    "answer",
    "xir_answer"
)

// 构造允许重设基址的 PE64 DLL，并声明所需的四个节。
const image0: map = format_pe64(
    format_pe_dll
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_required,
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
            ".edata",
            format_exports | format_readable
        ),
        format_section(
            ".reloc",
            format_fixups | format_readable | format_discardable
        )
    )
)
format_begin(image0);

// DLL 入口只报告成功；导出函数通过指针读取导出的整数。
format_section_begin(image0, ".text");
dll_entry:
    mov eax, 1
    ret

answer:
    mov rax, [rel answer_pointer]
    mov eax, [rax]
    ret

// 先为绝对指针保留固定宽度的真实文件字段。
answer_pointer:
    dq(0);
format_section_end(image0, ".text");

// 导出的数据保存在可读写节中。
format_section_begin(image0, ".data");
answer_value:
    dd(42);
format_section_end(image0, ".data");

// 根据导出列表生成完整的导出目录。
format_pe_export_section(
    image0,
    ".edata",
    exports,
    "answer.dll"
);

// 登记需要随映像基址变化而调整的绝对指针字段。
const relocs0: list = pe_reloc_new()
const relocs: list = format_pe_reloc_add(
    image0,
    relocs0,
    answer_pointer
)
format_pe_reloc_section(image0, ".reloc", relocs);

// 绑定加载器入口，并完成 DLL 文件映像。
const image: map = format_entry(image0, dll_entry)
format_finish(image);

// 布局稳定后，把导出数据在首选映像基址下的绝对地址写入指针字段。
defer {
    store.u64(answer_pointer, answer_value);
}
```

将它汇编为 64 位 `DLL`：

```powershell
# 使用 x86-64 目标平台生成 DLL 文件。
xirasm answer.asm --target x86-64 -o answer.dll
```

生成的 `DLL` 包含：

- 表示 `DLL` 的文件头标志；
- 位于 `dll_entry` 的加载器入口；
- 名为 `xir_answer` 的导出项，其相对虚拟地址指向 `answer`；
- 名为 `xir_answer_value` 的导出项，其相对虚拟地址指向 `answer_value`；
- 一项用于 `answer_pointer` 的 `DIR64` 基址重定位；
- 动态基址、高熵虚拟地址和数据页不可执行兼容标志。

## 指针值与重定位各有职责

示例中的三个操作共同完成绝对指针的构造。

首先，源代码预留一个真实存在的 64 位字段：

```text
answer_pointer:
    dq(0)
```

其次，布局完成后，收尾处理把按照首选映像基址计算的指针值写入该字段：

```text
store.u64(answer_pointer, answer_value)
```

最后，重定位列表告诉加载器：映像基址发生变化时，必须调整这个字段：

```text
format_pe_reloc_add(image0, relocs0, answer_pointer)
```

字段中存放的是按当前首选基址计算的指针值。`DIR64` 记录则指示加载器把基址差值应用到该字段。写入指针值和声明重定位缺一不可，任何一个操作都不能代替另一个。

函数本身使用相对于 `RIP` 的指令访问 `answer_pointer`，因此该指令不包含绝对映像地址。指针字段中保存的值是绝对地址，所以仍然需要重定位。

## `DLL` 的地址空间布局随机化策略

需要保证 `DLL` 能够改用其他基址时，可以使用 `format_pe_aslr_required`。如果格式方案中没有用途为 `format_fixups` 的节，该策略会拒绝该方案。

`format_pe_aslr_auto` 会在格式方案包含该节时启用动态基址标志。它适合用于同一种源代码结构可能包含、也可能不包含可重定位绝对地址字段的情况。

`format_pe_aslr_disabled` 会保持动态基址标志为关闭状态。只有 `DLL` 被有意固定在首选映像基址时，才应使用该策略。

仅仅存在 `.reloc` 节，并不能让任意绝对地址字段自动变得安全。每一个必须随已加载文件映像移动的字段，都需要单独声明重定位。

## PE32 使用 `HIGHLOW` 重定位

PE32 的构建流程相同，但使用与 32 位宽度对应的值：

| 事项 | PE32 `DLL` | PE64 `DLL` |
| --- | --- | --- |
| 导出声明 | `pe_export_use32` | `pe_export_use64` |
| 绝对指针字段 | `dd(0)` | `dq(0)` |
| 最终回填 | `store.u32` | `store.u64` |
| 生成的基址重定位 | `HIGHLOW` | `DIR64` |
| 默认映像基址 | `0x00400000` | `0x0000000140000000` |
| 高熵虚拟地址标志 | 不适用 | 为可重定位映像启用 |

`format_pe_reloc_add` 会根据格式方案种类选择 `HIGHLOW` 或 `DIR64`。使用常用格式接口时，源代码只传入字段标号，不需要自行选择重定位类型的数值。

导出函数必须遵循调用方预期的函数调用约定。PE64 导出通常采用 Windows `x64` 函数调用约定。PE32 导出则必须把所选的 32 位函数调用约定作为外部接口的一部分，并按该约定实现函数。

## 从其他语言调用 `DLL`

任何能够加载 Windows `DLL` 并按名称查找导出项的语言，都可以使用生成的文件映像。下面的 `C#` 程序调用函数导出并读取数据导出：

```csharp
using System;
using System.Runtime.InteropServices;

internal static class Program
{
    // 使用 Windows 加载器接口载入 DLL，并按名称查找导出地址。
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryW(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    private static extern IntPtr GetProcAddress(
        IntPtr module,
        string name
    );

    // 函数声明必须与汇编导出采用相同的函数调用约定。
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Answer();

    private static int Main()
    {
        // 载入 DLL，失败时返回单独的退出状态。
        IntPtr module = LoadLibraryW("answer.dll");
        if (module == IntPtr.Zero)
            return 1;

        // 分别取得函数导出和数据导出的地址。
        IntPtr functionAddress = GetProcAddress(module, "xir_answer");
        IntPtr dataAddress = GetProcAddress(module, "xir_answer_value");
        if (functionAddress == IntPtr.Zero || dataAddress == IntPtr.Zero)
            return 2;

        // 把函数地址转换为可调用对象，并从数据地址读取整数。
        Answer answer =
            Marshal.GetDelegateForFunctionPointer<Answer>(functionAddress);
        int value = Marshal.ReadInt32(dataAddress);

        // 同时核对函数返回值和导出数据。
        return answer() == 42 && value == 42 ? 0 : 3;
    }
}
```

外部调用方只需要了解 `DLL` 文件、导出名称和函数调用约定，不依赖 XIRASM 源代码中的标号、节表项位置或重定位表位置。

## 加载到其他基址

首选地址不可用时，加载器会选择另一个基址，并计算：

```text
基址差值 = 实际加载基址 - 首选基址
```

对于每一项 `DIR64` 或 `HIGHLOW` 重定位，加载器都会把这个差值加到相应字段中。在上面的示例里，调整后的 `answer_pointer` 仍然指向已经移动的 `answer_value`，因此导出函数仍会返回 42。

这就是重定位目录在程序运行时的含义。只有目录结构并不足够；重定位项必须标识正确的字段，该字段也必须保存按首选基址计算的正确值。

## 常见 `DLL` 错误

### 意外导出 `DLL` 入口

加载器入口和公开接口是两套独立接口。只导出确实需要供外部调用方使用的标号。

### 遗漏导出节

`format_pe_export_section` 要求格式方案中已经声明一个用途为 `format_exports` 的节。

### 手工打开 `.edata` 或 `.reloc`

常用导出和重定位辅助接口会自行管理这些节的构建流程。不要再在外层添加节开始和结束调用。

### 忘记回填字段

重定位记录不会初始化字段。每一个保存原始绝对地址的字段，都必须写入布局稳定后的首选基址地址。

### 忘记声明重定位

在首选基址下正确的指针，改用其他基址后可能失效。所有需要随文件映像移动的绝对地址字段都必须声明重定位。

### 导出函数与调用约定不兼容

导出表只公开地址，不记录函数调用约定。汇编例程和其他语言中的声明必须在参数、返回结果、栈状态以及需要保持的寄存器方面完全一致。

## 实用 `DLL` 规则

1. 选择 `format_pe_dll`，并提供只完成少量工作的加载器入口。
2. 将导出函数和导出数据与 `DLL` 入口分开。
3. 使用目标标号和公开名称构建一份不可变的导出列表。
4. 声明一个可读、用途为 `format_exports` 的节。
5. 由 `format_pe_export_section` 生成完整的导出目录。
6. 使用固定宽度的占位字段保存绝对指针。
7. 把每个指针按稳定布局计算出的首选基址地址回填到字段中。
8. 通过 `format_pe_reloc_add` 登记每一个可重定位的绝对地址字段。
9. 写出一个可读、可丢弃且用途为 `format_fixups` 的节。
10. 使用真实的其他语言调用程序，并让 `DLL` 在非首选基址加载，以确认导出和重定位行为。

第 8 章将在最小可执行文件和 `DLL` 构建流程之外，介绍资源数据和可选的 PE 校验和。

[返回可执行文件格式指南](../formats.md)
