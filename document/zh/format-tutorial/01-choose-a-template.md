# 1. 先选输出类型

写格式文件，第一步是确定要输出哪一种文件。这一步决定后面所有字段：PE 映像用节表描述内容，ELF 可执行文件用程序头描述内容，目标文件既没有入口地址，也没有装载段。文件类型选错，声明的节或装载段就无法写进输出文件。

`format.inc` 把常见的输出归纳成几组入口函数。这一层是包装层：使用方声明目标文件类型、节或装载段、入口位置，头部、节表或程序头、文件偏移、RVA、对齐以及全部回填字段都由它生成。

## 统一入口

```asm
// 声明节或装载段，其余格式结构交给 format.inc。
import("format/format.inc")
```

直接导入 `pe.inc`、`elfexe.inc`、`elfobj.inc` 这几个文件，文件头、目录和表项都要自己填。只有 `format.inc` 表达不了目标布局时，才改用[高级格式构造指南](../../advanced-formats.md)。

## 配置函数

| 输出 | 配置函数 | 内容描述 | 选项 |
| --- | --- | --- | --- |
| PE32 可执行文件或 DLL | `format_pe32(options, sections)` | `format_section(...)` | 必填 |
| PE64 可执行文件或 DLL | `format_pe64(options, sections)` | `format_section(...)` | 必填 |
| PE64 可执行文件或 DLL，机器由参数给出 | `format_pe64_machine(options, sections, machine)` | `format_section(...)` | 必填 |
| PE64 AArch64 可执行文件或 DLL | `format_pe64_arm64(options, sections)` | `format_section(...)` | 必填 |
| COFF32 目标文件 | `format_coff32(sections)` | `format_section(...)` | 无 |
| COFF64 目标文件 | `format_coff64(sections)` | `format_section(...)` | 无 |
| COFF64 目标文件，机器由参数给出 | `format_coff64_machine(sections, machine)` | `format_section(...)` | 无 |
| COFF64 AArch64 目标文件 | `format_coff64_arm64(sections)` | `format_section(...)` | 无 |
| ELF32 可执行文件 | `format_elf32(options, segments)` | `format_segment(...)` | 必填，只能是 `format_elf_exec` |
| ELF64 可执行文件 | `format_elf64(options, segments)` | `format_segment(...)` | 必填 |
| ELF64 AArch64 可执行文件 | `format_elf64_aarch64(options, segments)` | `format_segment(...)` | 必填 |
| ELF32 目标文件 | `format_elfobj32(sections)` | `format_section(...)` | 无 |
| ELF64 目标文件 | `format_elfobj64(sections)` | `format_section(...)` | 无 |
| ELF64 AArch64 目标文件 | `format_elfobj64_aarch64(sections)` | `format_section(...)` | 无 |
| ELF64 共享库 | `format_elf64_so(soname, segments)` | `format_segment(...)` | 无，库名由 `soname` 给出 |
| ELF64 AArch64 共享库 | `format_elf64_so_aarch64(soname, segments)` | `format_segment(...)` | 无，库名由 `soname` 给出 |

ELF 可执行文件的选项是 `format_elf_exec` 或 `format_elf_pie`，二选一。共享库不接收选项，文件类型由函数本身确定。ELF32 层只支持可执行模式，传入 `format_elf_pie` 会报 `format.inc ELF32 layer currently supports executable mode`。

机器通常是固定的：`format_pe64` 就是 x86-64，`format_coff64` 就是 AMD64。机器名来自配置、需要在运行时选定目标时，用带 `machine` 参数的那两个构造函数，例如 `format_pe64_machine(options, sections, pe_machine_arm64)`。

## 节描述

PE、COFF 和 ELF 目标文件按节组织内容。一个节用 `format_section(name, attributes)` 声明，两个参数：

| 参数 | 写什么 |
| --- | --- |
| `name` | 节名，例如 `".text"`、`".data"`、`".bss"`、`".idata"` |
| `attributes` | 一个用途标志，加上需要的权限标志 |

用途说明这个节装什么，每个节**只能给一个**：

| 用途 | 装什么 |
| --- | --- |
| `format_code` | 指令 |
| `format_data` | 已初始化数据或只读常量 |
| `format_uninitialized_data` | 零初始化内存，也就是 BSS |
| `format_imports` | PE 导入表 |
| `format_exports` | PE 导出表 |
| `format_resources` | PE 资源 |
| `format_fixups` | PE 基址重定位表 |

权限说明这个节在运行时的访问方式，可以叠好几个：

| 权限 | 含义 |
| --- | --- |
| `format_readable` | 运行时可读 |
| `format_writeable` | 运行时可写 |
| `format_executable` | 运行时可执行 |
| `format_discardable` | 加载后可丢弃的元数据 |

常用组合：

| 内容 | 推荐属性 |
| --- | --- |
| 代码 | `format_code \| format_readable \| format_executable` |
| 只读数据 | `format_data \| format_readable` |
| 可写数据 | `format_data \| format_readable \| format_writeable` |
| BSS | `format_uninitialized_data \| format_readable \| format_writeable` |
| PE 导入表 | `format_imports \| format_readable \| format_writeable` |
| PE 导出表 | `format_exports \| format_readable` |
| PE 资源 | `format_resources \| format_readable` |
| PE 重定位表 | `format_fixups \| format_readable \| format_discardable` |

节名必须唯一。PE 和 COFF 的节名最长八字节，超了报 `PE/COFF section names must fit in eight bytes`。`format_imports`、`format_exports`、`format_resources`、`format_fixups` 这四种用途，在一个配置里各只能出现一次，重复报 `format special-purpose section is duplicated`。

## 装载段描述

ELF 可执行文件和 ELF 共享库不按节组织，按装载段组织：程序头描述的就是装载段，加载器据此把文件映射进内存。装载段用 `format_segment(name, attributes)` 声明，与 `format_section(name, attributes)` 对应：

| 参数 | 写什么 |
| --- | --- |
| `name` | 装载段名，例如 `".text"`、`".rodata"`、`".data"`、`".bss"` |
| `attributes` | `format_load` 加权限标志 |

`format_load` 是这一层唯一支持的装载段用途。权限还是那三项：`format_readable`、`format_writeable`、`format_executable`。装载段没有可丢弃这个属性，写 `format_discardable` 会报 `unknown format segment attribute`。

| 内容 | 推荐属性 |
| --- | --- |
| 代码 | `format_load \| format_readable \| format_executable` |
| 只读数据 | `format_load \| format_readable` |
| 可写数据 | `format_load \| format_readable \| format_writeable` |
| BSS | `format_load \| format_readable \| format_writeable` |

装载段名同样必须唯一，重复报 `format segment name is duplicated`。

## 完整流程

下面是一个最小的 PE64 控制台程序。它声明 `.text` 和 `.bss`，PE 头、节表、入口字段，以及 BSS 的文件大小与内存大小之差，全部由 `format.inc` 生成：

```asm id=pe64-minimal target=x86-64
import("format/format.inc")

// 四个选项：可执行文件、控制台子系统、开启 NX、关闭 ASLR。
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        // 代码节：可读可执行。
        format_section(".text", format_code | format_readable | format_executable),
        // BSS 节：可读可写，只占内存地址。
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)

// 开始输出，头部和节表的空间在这里预留。
format_begin(image)

format_section_begin(image, ".text")
start:
    xor eax, eax
    ret
format_section_end(image, ".text")

// BSS 只占内存地址，不写文件字节。
format_section_begin(image, ".bss")
scratch:
    rb(64)
format_section_end(image, ".bss")

// 设入口地址，然后回填全部字段。
format_entry_mut(image, start)
format_finish(image)
```

结果是 1024 字节的合法 PE：`MZ` 头，`PE\0\0` 签名，机器码 `0x8664`（x86-64），入口 RVA `0x1000`，节表里两个节，`.bss` 的文件大小是 0、内存大小是 64。

顺序分五步，错一步输出就不对：

1. 先用 `let image: map = ...` 建立配置；
2. 再调用 `format_begin(image)` 预留头部和表项；
3. 内容必须写进已经声明过的节；
4. 可执行文件用 `format_entry_mut(image, start)` 设入口；
5. 最后调用 `format_finish(image)` 完成全部回填。

第 3 步到第 5 步之间不能漏掉 `format_section_end`。漏了不报错，汇编仍然成功，但节表那一行定不下来：文件从 1024 字节缩到 515 字节，`.text` 的文件大小停在 3，也就是它的逻辑长度，没有按 512 字节的文件对齐补齐。这种文件加载器会直接拒绝。

## ELF 可执行文件

ELF 可执行文件把 `format_section` 换成 `format_segment`，把 `format_section_begin` / `format_section_end` 换成 `format_segment_begin` / `format_segment_end`，其余顺序一模一样：

```asm id=elf64-minimal target=x86-64
import("format/format.inc")

// 选项 format_elf_exec 表示固定地址可执行文件；换成 format_elf_pie 就是 PIE。
let image: map = format_elf64(
    format_elf_exec,
    list.of(
        // 装载段：可读可执行，由加载器映射进内存。
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

format_begin(image)

format_segment_begin(image, ".text")
start:
    // 系统调用 60：exit(0)。
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text")

format_entry_mut(image, start)
format_finish(image)
```

结果是 137 字节的 ELF 映像：`\x7fELF` 魔数，64 位小端，类型 `ET_EXEC`（2），机器 `EM_X86_64`（62），入口 `0x400080`，一个 `PT_LOAD` 程序头，权限 `R|X`，文件大小 9 字节、内存大小 9 字节，页对齐 `0x1000`。

两种类型不能混用。ELF 映像配 `format_section`，报 `an ELF image plan declares segments, not sections`；反过来，PE 配 `format_segment`，报 `only an ELF image plan declares segments`。目标文件和 ELF 共享库没有普通可执行文件入口，对它们调用 `format_entry_mut`，报 `format plan does not use an executable entry`。
