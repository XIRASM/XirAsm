# 5. 通用规则和常见错误

格式文件出错时，绝大多数问题不在 PE、ELF 的字段细节上，而在声明本身：节名写错、一个节给了多种用途、权限给得与运行时需求不符、调用顺序颠倒。头部和表项由 `format.inc` 依据声明生成；声明与意图不一致时，产出的文件在结构上依然合法，只是并非所需。

下面按「先看错误是什么样，再讲如何避免」的顺序排列。每条规则都附一条真实诊断或可核对的结果，可直接用于对照源文件。

## 不要混用两套写法

正常程序只导入一个文件：

```asm id=only-one-layer
import("format/format.inc")
```

不要在同一个文件里既用 `format.inc` 的生命周期函数，又手写 PE/ELF 头部或表项。两套写法同时负责同一张表时，最终文件里会出现两个都要填同一个字段的值，先写入的被覆盖，而无法判断哪一个生效。需要完全控制字段时，整份文件都改用[高级格式构造指南](../../advanced-formats.md)。

节和装载段的混用也会被抓出来，因为两种计划的键不同：ELF 映像配 `format_section` 报 `an ELF image plan declares segments, not sections`；PE 配 `format_segment` 报 `only an ELF image plan declares segments`。

## 可变配置必须是 `let`

`_mut` 结尾的函数要改写传入的绑定，所以该实参必须是一个可以改写的 `let`：

```asm id=mut-requires-let
import("format/format.inc")

// 配置要被 _mut 函数改写，所以用 let 而不是 const。
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable)
    )
)
format_begin(image)
format_section_begin(image, ".text")
start:
    ret
format_section_end(image, ".text")
format_entry_mut(image, start)
format_finish(image)
```

下面三种写法都不合法，报错各不相同：

| 写法 | 诊断 |
| --- | --- |
| `const image: map = format_pe64(...)` 之后调 `_mut` | `mutable function argument must resolve to a let binding` |
| 直接把构造函数的结果传给 `_mut` | `mutable function argument must be a direct let binding` |
| 传 `map.get(holder, "image")` 这类字段取值 | 同上，解析不到绑定 |

区别在于：**只读的描述值可以放进 `const`**，例如 `format_section(...)`、`format_segment(...)`、`format_coff_public(...)` 的返回值；**会被 `_mut` 函数改写的配置或集合必须用 `let`**。

## 先声明，再写内容

传给 `format_section_begin`、`format_section_end`、`format_segment_begin`、`format_segment_end` 的名字，必须已经出现在配置的节或装载段列表里：

```text
// 配置里声明了哪些，就只能写哪些。
format_section(".text", format_code | format_readable | format_executable)
```

写一个没有声明过的节，报 `format section is not declared`。该诊断指向 `format_section_begin` 那一行，但需要修改的是配置里遗漏的声明。

## 每个描述只选一个用途

一个节只能是代码、数据、BSS、导入、导出、资源、基址重定位中的一种。同时给两种用途，报 `format section has multiple purposes`：

```text
// 不合格：一个节同时声称是代码和数据。
format_section(".mixed", format_code | format_data | format_readable)
```

用途之外的部分是权限，可以叠加；用途本身不能叠加。ELF 装载段目前只有 `format_load` 一种用途，没有第二个可选项。

## 权限按运行时需求给

| 内容 | 常见权限 |
| --- | --- |
| 指令 | 可读、可执行 |
| 常量和字符串 | 可读 |
| 可修改数据 | 可读、可写 |
| BSS | 可读、可写 |
| PE 导入表 | 可读、可写 |
| PE 基址重定位表 | 可读、可丢弃 |

除了自修改代码或特殊加载场景，不要把代码节标成可写，也不要把数据节标成可执行。多给的权限不会报错，但会让加载器放开本来该拦住的写入或执行。

## BSS 是内存大小，不是文件内容

`format_uninitialized_data` 声明的是「运行时需要一段零初始化内存」。这一节里用 `rb(...)`、`reserve(...)` 这类预留操作登记大小：

```asm id=bss-reserved-only target=x86-64
import("format/format.inc")

// BSS 的正确写法：只用 rb() 预留大小，不写初始化字节。
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    ret
format_section_end(image, ".text")

// rb(8) 只登记内存大小，文件里不占字节。
format_section_begin(image, ".bss")
scratch:
    rb(8)
format_section_end(image, ".bss")

format_entry_mut(image, start)
format_finish(image)
```

这样写出来的 `.bss` 文件大小是 0、内存大小是 8。

反过来，在 `.bss` 里写真实字节**不会报错**，但结果自相矛盾：节的属性仍是 `IMAGE_SCN_CNT_UNINITIALIZED_DATA`（声明没有初始化数据），文件大小却不再是 0。把上面那行替换为 `dd(0x11223344)` 与 `dd(0x55667788)`，`.bss` 的文件大小变为 512——按文件对齐补齐后多占一个完整块，而加载器按属性仍然认为这段不需要从文件读取。文件能够装配出来，含义却是错的，因此这类字节应写在 `format_data` 的节里。

## 重定位不是指针

写指针值和声明重定位是两件事，两件都要做：

```asm id=reloc-not-pointer
import("format/format.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    ret
worker:
    mov eax, 42
    ret
format_section_end(image, ".text")

// 槽先按最终宽度写出来，defer 里只改值。
format_section_begin(image, ".data")
worker_pointer:
    dq(0)
format_section_end(image, ".data")

let relocs: list = pe_reloc_new()
// 参数是保存地址的槽，不是被指向的 worker。
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs)

format_entry_mut(image, start)
format_finish(image)

// 地址稳定后再回填数值。
defer {
    store.u64(worker_pointer, worker)
}
```

`format_pe_reloc_add_mut` 接收的是**槽的地址**。传入目标标签 `worker` 不会报错，但生成的记录指向 `.text` 中某条指令的内部，加载器更换基址时会去修改一个不属于任何槽的位置；上例若传入 `worker`，记录落在 `0x1001`，正是 `.text` 内部。核对方法是将记录中的 RVA 与节表对照，它必须落在 `.data` 的槽上。

`defer` 中回填数值是允许的，因为数值不改变文件大小；上例的 `store.u64` 就放在 `defer` 里。

## 入口只属于可执行输出

PE 可执行文件、PE DLL、ELF 可执行文件要设入口：

```text
format_entry_mut(image, start)
```

COFF 目标文件、ELF 目标文件和 ELF 共享库都不使用入口这条路。给它们设置入口，报 `format plan does not use an executable entry`；反过来，PE 或 ELF 可执行文件缺少入口时，`format_finish` 报 `PE executable or DLL requires an entry address` 或 `ELF executable requires an entry address`。

## 表项挂载的时机

只有一类函数必须在 `format_begin` **之前**调用：把符号表、重定位表、导入导出元数据挂到配置上的 `format_*_tables_mut`，例如 `format_coff_tables_mut`、`format_elfobj_tables_mut`、`format_elfexe_tables_mut`、`format_elfso_tables_mut`。它们决定头部和动态表需要预留多少空间，因此要在开始输出之前交出数据。

PE 的几个节生成函数不受该限制。`format_pe_import_section`、`format_pe_export_section`、`format_pe_resource_section`、`format_pe_reloc_section` 都是写出节内容，放在 `format_begin` 之后、`format_finish` 之前调用；在 `format_begin` 之后调用时，导入目录同样被正确注册（`RVA = 0x2040`、`size = 40`）。它们唯一的要求是不要自行再套一层 `format_section_begin` 去打开同一个节。

## `defer` 只做最终回填

`defer` 适合回填地址、写指针槽、计算校验和这类不改变布局的操作。往其中写入内容会报错：

```text
// 不合格：在 defer 里写节内容。
defer {
    format_section_begin(image, ".text")
    dd(0x11223344)
    format_section_end(image, ".text")
}
```

诊断是 `FinalizerCannotChangeLayout`。参与布局的字节必须在 `format_finish` 之前写完，`defer` 只在最终字节确定之后修改数值。

## 有些错误由用法决定

上面每条错误都有诊断或可核对的结果，但有几类错误 `format.inc` 不会拦，只能靠写法本身避免：

| 情况 | 后果 |
| --- | --- |
| `.bss` 里写真实字节 | 装配成功，节属性与文件内容矛盾，且多占一个文件块 |
| 重定位记录指向目标标签 | 装配成功，记录指向无关位置 |
| 漏写 `format_section_end` | 装配成功，节表行没有定型，文件被截短 |
| 跨语言调用时不按 ABI 放置参数寄存器 | 装配和链接都成功，运行结果错误 |

这四类问题都不会有任何提示，因此修改这几处之后必须**核对产物**：用 `llvm-readobj` 读节表和目录，或在真机运行一遍查看退出码。第 3 章和第 4 章给出了具体的核对命令。
