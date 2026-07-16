# XIRASM 格式教程

这份教程介绍 XIRASM 的常用格式接口。你只需要先确定要生成哪种文件，再按模板声明节、段、导入、导出和重定位。PE、COFF、ELF 的字段计算由格式封装完成。

普通程序统一从这里开始：

```asm
import("format/format.inc");
```

`include/format/` 提供三层接口：

- `format.inc` 是普通用户入口，负责格式配置、命名节或段以及常用表。
- `pe32.inc`、`pe64.inc`、`elf32.inc`、`elf64.inc` 是兼容用的位宽包装。
- `pe.inc`、`elfexe.inc`、`elfobj.inc` 等提供直接控制，适合标准模板无法表达的文件。

本教程完整说明 `format.inc`。需要直接控制字段和表项时，再阅读[高级格式构造指南](../advanced-formats.md)。

## 章节

1. [选择模板](format-tutorial/01-choose-a-template.md)
2. [Windows PE 和 DLL](format-tutorial/02-windows-pe.md)
3. [Linux ELF 可执行文件和共享库](format-tutorial/03-linux-elf.md)
4. [COFF 和 ELF 目标文件](format-tutorial/04-object-files.md)
5. [通用规则和常见错误](format-tutorial/05-common-rules.md)

## 快速选择

| 输出文件 | 构造函数 | 主要接口 |
| --- | --- | --- |
| Windows 可执行文件 | `format_pe32` 或 `format_pe64` | `format_section_begin`、`format_entry_mut`、`format_finish` |
| Windows DLL | `format_pe32` 或 `format_pe64`，选用 `format_pe_dll` | `format_pe_export_pairs_mut`、`format_pe_export_section` |
| Linux 可执行文件 | `format_elf32` 或 `format_elf64`，选用 `format_elf_exec` | `format_segment_begin`、`format_entry_mut`、`format_finish` |
| Linux PIE | `format_elf64`，选用 `format_elf_pie` | `format_segment_begin`、`format_entry_mut`、`format_finish` |
| Linux 共享库 | `format_elf64_so` | `format_elfso_tables_mut`、`format_segment_begin`、`format_finish` |
| COFF 目标文件 | `format_coff32` 或 `format_coff64` | `format_coff_tables_mut`、`format_section_begin`、`format_finish` |
| ELF 目标文件 | `format_elfobj32` 或 `format_elfobj64` | `format_elfobj_tables_mut`、`format_section_begin`、`format_finish` |

## 基本流程

所有普通格式都遵循同一顺序：

```text
1. 用构造函数创建 let 格式配置。
2. 按需用 *_mut 接口添加导入、导出、符号或重定位。
3. 调用 format_begin。
4. 在已声明的节或段中写入代码和数据。
5. 可执行文件用 format_entry_mut 设置入口。
6. 调用 format_finish。
```

构造函数返回新值，例如 `format_pe64(...)` 和 `format_section(...)`。名称以 `_mut` 结尾的过程会直接修改传入的 `let` 绑定：

```text
let image: map = format_pe64(options, sections)
format_entry_mut(image, start)
format_finish(image);
```

不要把 `const`、临时表达式或字段访问传给 `_mut` 参数。
