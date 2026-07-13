# XIRASM

[English](README.md)

**一门同时支持 x86、x86-64、RV32 与 RV64，并拥有真正编译期语言的现代汇编器。**

XIRASM 面向真正写汇编的人：保留汇编的直接控制，同时摆脱陈旧的伪指令体系和
脆弱的文本宏技巧。

指令照常写。当源码需要计算、生成、复用或转换时，直接使用类型值、函数、控制流、
集合、模块、文件数据与 token matching。

一套汇编器，一门语言，同时覆盖多种指令集与原生输出格式。

## 为什么选择 XIRASM

- **一套汇编器同时支持 x86 与 RISC-V。** x86、x86-64、RV32 和 RV64 共用同一门
  语言与项目模型。
- **用编译期程序代替宏谜题。** 使用函数、表达式、`if`、`while` 和 `for`
  直接表达意图，不再把复杂逻辑塞进文本替换。
- **代码和数据生成就是普通语言能力。** 批量生成指令、表格、声明、常量与
  二进制数据，不必额外维护一套源码生成器。
- **可以建立可复用库和小型 DSL。** 汇编阶段可以使用 module、list、map、
  string、bytes、JSON、TOML、文件 API 与 token matching。
- **同一工具直接产出实用文件。** 支持 flat binary、Windows EXE/DLL、COFF
  object、Linux executable/PIE、ELF object 与 ELF shared library。

## 汇编，也可以拥有正常的语言能力

指令仍然是汇编；重复工作交给普通的编译期代码：

```asm
x86.use64();

fn emit_square_table(count: u8) {
    for value in range(0, count) {
        dd(value * value);
    }
}

const answer: u32 = 40 + 2

entry:
    mov eax, answer
    ret

table:
emit_square_table(4);
```

函数与循环只在汇编阶段执行，最终输出中只有机器码和生成的表格。

同一门语言还提供：

- 类型化常量与变量；
- 可复用函数与词法作用域；
- list、map、string 与 bytes；
- struct、union、pack、alignment 与 reserve；
- module 与 import；
- JSON、TOML 与文件驱动生成；
- 用于小型源码 DSL 的 token matching；
- assert 与诊断能力。

## 支持的目标

| CLI 目标 | 指令集 |
| --- | --- |
| `x86-64`、`x64`、`x86_64` | 64 位 x86 |
| `x86`、`x86-32` | 32 位 x86 |
| `rv64`、`riscv64` | 64 位 RISC-V |
| `rv32`、`riscv32` | 32 位 RISC-V |

切换目标时，编译期语言与项目组织方式保持一致。

## 支持的输出格式

XIRASM 可以直接生成：

- flat binary 与应用专用二进制；
- PE32、PE64 Windows EXE 与 DLL；
- COFF32、COFF64 object；
- ELF32、ELF64 executable；
- ELF64 PIE；
- ELF32、ELF64 object；
- ELF64 shared library。

可执行格式项目使用普通格式库：

```asm
import("format/format.inc");
```

CLI 也可以直接创建可构建的 Windows 与 Linux 起始项目。PE、COFF 与 ELF 的完整
用法放在[可执行格式指南](document/formats.md)中。

## 快速开始

使用 Zig 0.17 构建 XIRASM：

```powershell
zig build -Doptimize=ReleaseFast
```

汇编 flat binary：

```powershell
xirasm hello.asm --target x86-64 -o hello.bin
```

创建并构建 Windows executable 项目：

```powershell
xirasm init hello-win --isa x86-64 --os windows --abi msvc
cd hello-win
xirasm build
```

创建并构建 Linux executable 项目：

```powershell
xirasm init hello-linux --isa x86-64 --os linux --abi sysv
cd hello-linux
xirasm build
```

## 编辑器支持

独立的 [XIRASM VS Code 扩展](https://codeberg.org/kukuyun/xirasm-vscode)
提供语法高亮、补全、导航与编译器诊断。

## 文档

- [完整中文文档 PDF](document/zh/pdf/xirasm-documentation-zh-CN.pdf) - 合并语言指南、
  可执行格式指南与语言 API 参考，适合离线阅读。
- [中文语言指南](document/zh/language.md) - 学习编译期语言与汇编模型。
- [中文可执行格式指南](document/zh/formats.md) - 使用普通格式 API 构造 PE、COFF
  与 ELF 程序。
- [中文语言 API 参考](document/zh/api-reference.md) - 查询语法与内置 API。
- [高级格式构造指南（英文）](document/advanced-formats.md) - 需要手动控制时使用直接
  格式 helper。

## 状态

当前版本：**0.2.5**

XIRASM 仍处于 1.0 之前，公开 API 在稳定版之前可能继续收敛。

## 许可证

Apache-2.0。
