# XIRASM 格式教程

这份教程是使用 XIRASM 生成 PE、ELF、COFF 等常见输出文件的入口。它讲的是 `format/format.inc` 提供的高层封装：用户只需要描述“我要什么文件、有哪些节或装载段、入口在哪里、需要哪些导入导出和重定位”，格式层会负责生成头部、表项、文件偏移、RVA、对齐和最终回填。

如果你过去主要在 C、C++、Rust 或其他语言里写内联汇编，文件格式通常由编译器、链接器和运行时处理。XIRASM 直接生成输出文件，所以你需要明确回答这些问题：

- 程序从哪个标签开始执行；
- 哪些字节是代码，哪些字节是数据；
- 哪些范围在运行时可读、可写或可执行；
- 哪些范围只占内存大小，不占初始化文件内容；
- 需要导入或导出哪些外部符号；
- 文件里哪些绝对地址需要让加载器或链接器修正；
- 最终阶段需要回填哪些地址、校验和或表项字段。

普通格式教程只需要一个导入：

```asm
import("format/format.inc");
```

`include/format/` 下有多层文件：

- `format.inc` 是普通用户入口，提供格式配置、节/装载段描述、导入、导出、资源、重定位、符号表和最终生成流程；
- `pe32.inc`、`pe64.inc`、`elf32.inc`、`elf64.inc` 是按位宽封装的薄层，普通教程不从这里开始；
- `pe.inc`、`elfexe.inc`、`elfobj.inc` 等文件提供更低层的表项和字段构造函数，适合必须手写格式细节的高级场景。

本教程只覆盖 `format.inc` 的常规封装层。需要手写 PE/ELF 头部、目录、节表、程序头或动态表时，再阅读[高级格式构造指南](../advanced-formats.md)。

## 章节

1. [选择模板](format-tutorial/01-choose-a-template.md)
2. [Windows PE 和 DLL](format-tutorial/02-windows-pe.md)
3. [Linux ELF 可执行文件和共享库](format-tutorial/03-linux-elf.md)
4. [COFF 和 ELF 目标文件](format-tutorial/04-object-files.md)
5. [通用规则和常见错误](format-tutorial/05-common-rules.md)

## 快速选择

| 目标 | 起始函数 | 主要操作 |
| --- | --- | --- |
| Windows 可执行文件 | `format_pe32` 或 `format_pe64` | `format_section_begin`、`format_pe_import_section`、`format_pe_resource_section`、`format_pe_reloc_section` |
| Windows DLL | `format_pe32` 或 `format_pe64`，选项包含 `format_pe_dll` | `format_pe_export_section`，可选导入、资源和重定位 |
| Linux 可执行文件 | `format_elf32` 或 `format_elf64`，选项为 `format_elf_exec` | `format_segment_begin`、`format_entry_mut`、`format_finish` |
| Linux PIE | `format_elf64`，选项为 `format_elf_pie` | `format_segment_begin`、`format_entry_mut`、`format_finish` |
| Linux 共享库 | `format_elf64_so` | `format_elfso_tables_mut`、`format_segment_begin`、`format_finish` |
| COFF 目标文件 | `format_coff32` 或 `format_coff64` | `format_coff_tables_mut`、`format_section_begin`、`format_finish` |
| ELF 目标文件 | `format_elfobj32` 或 `format_elfobj64` | `format_elfobj_tables_mut`、`format_section_begin`、`format_finish` |

## 基本生命周期

高层格式配置都遵循同一条主线：

```text
import("format/format.inc");

// 1. 创建格式配置：文件族、位宽、权限、节或装载段。
let image: map = ...

// 2. 可选：把导入、导出、符号表或重定位表挂到配置上。
format_*_tables_mut(image, ...)

// 3. 开始输出文件。格式层会在这里预留头部和表项空间。
format_begin(image);

// 4. 在已经声明过的节或装载段里写代码和数据。
format_section_begin(image, ".text");
start:
    ret
format_section_end(image, ".text");

// 5. 可执行文件设置入口，然后完成输出。
format_entry_mut(image, start)
format_finish(image);
```

构造函数和描述函数会返回值，例如 `format_pe64(...)`、`format_section(...)`、`format_segment(...)`。名称以 `_mut` 结尾的函数是语句式更新函数，会直接修改传入的 `let` 绑定：

```text
let image: map = format_pe64(options, sections)
format_entry_mut(image, start)
format_finish(image);
```

需要更新同一个配置时，继续使用同一个 `let` 绑定即可。`_mut` 函数的可变参数必须是直接的 `let` 绑定，不能是 `const`、临时表达式、字段访问或函数返回值。

## 使用原则

- 先选输出文件类型，再写节、装载段和表项；不要从 PE/ELF 原始字段开始推。
- PE、COFF、ELF 目标文件使用 `format_section(...)`；ELF 可执行文件和共享库使用 `format_segment(...)`。
- 普通层会派生头部、表项、对齐、RVA、文件偏移和最终回填；你只负责描述内容边界和必要元数据。
- 同一文件不要混用普通 `format.inc` 流程和底层手写表项流程，除非你明确转向高级格式构造。
- 能从最小 `.text` 模板开始，就先让最小模板跑通，再逐步加入导入、导出、资源、重定位和 BSS。
