# XIRASM

[English](README.md) | [项目网站](https://xirasm-site.pages.dev/) | [版本更新](https://xirasm-site.pages.dev/#updates)

**指令使用自然汇编语法，外围能力使用真正的编译期语言。**

XIRASM 面向真正写汇编的人：保留汇编的直接控制，同时摆脱陈旧的伪指令体系和
脆弱的文本宏技巧。

指令照常写。当源码需要计算、生成、复用或转换时，直接使用类型值、函数、控制流、
集合、模块、文件数据与 token matching。

最终得到的是一门统一的汇编器语言：同时处理手写指令、代码生成、二进制布局与
原生输出格式，并覆盖 x86、RISC-V 与 SPIR-V。

## 核心区别

- **ISA 文本保持自然。** 标号与处理器指令直接书写，不需要给每条汇编指令套上
  函数调用。
- **用编译期程序代替文本宏谜题。** 类型值、函数、词法作用域、`if`/`else if`、
  `while`、`for`、`break` 和 `continue` 可以直接表达生成逻辑。
- **数据与格式共用同一门语言。** struct、union、浮点与整数写出、reserve、module、
  文件、JSON、TOML、list、map 与 token matching 可以直接组合，不再存在第二套
  伪指令方言。
- **前端明确拥有汇编语义。** source span、symbol、fragment、fixup、layout、
  relaxation、diagnostic 与 output 都是显式状态；ISA encoder 只是窄后端。
- **多种指令集共用项目模型。** x86、x86-64、RV32、RV64 与 SPIR-V 使用相同的
  编译期语言和工程组织方式。

## 直接看代码

指令仍然是汇编；重复工作交给普通的编译期代码：

```asm
x86.use64();

fn emit_square_table(count: u8) {
    for value in range(0, count) {
        dd(value * value);
    }
}

const answer: u32 = 40 + 2;

entry:
    mov eax, answer
    ret

table:
emit_square_table(4);
```

函数与循环只在汇编阶段执行，最终输出中只有机器码和生成的表格，不包含运行时解释器。

同一门语言还提供：

- 类型化常量与变量；
- 可复用函数与词法作用域；
- list、map、string 与 bytes；
- struct、union、pack、alignment 与 reserve；
- module 与 import；
- JSON、TOML 与文件驱动生成；
- 用于小型源码 DSL 的 token matching；
- assert 与带源码位置的诊断能力。

## 快速开始

使用 Zig 0.17 构建：

```text
zig build -Doptimize=ReleaseSafe
```

新建 `hello.asm`：

```asm
x86.use64();

entry:
    mov eax, 42
    ret
```

使用仓库刚构建的程序汇编 flat binary：

```text
./zig-out/bin/xirasm hello.asm --target x86-64 -o hello.bin
```

Windows 下运行 `zig-out\bin\xirasm.exe`。已经安装到 `PATH` 的 `xirasm` 可以直接
调用。

生成可以直接构建的原生项目：

```text
xirasm init hello-win --isa x86-64 --os windows --abi msvc
xirasm init hello-linux --isa x86-64 --os linux --abi sysv
```

每个生成项目都包含 `xirasm.toml`；进入项目后运行 `xirasm build`，即可按配置的
源码和输出路径完成汇编。

CLI 子命令必须写在其选项之前。例如应写 `xirasm build --timings`，不要写成
`xirasm --timings build`。

## 支持的目标

| CLI 目标 | 指令集 |
| --- | --- |
| `x86-64`、`x64`、`x86_64` | 64 位 x86 |
| `x86`、`x86-32` | 32 位 x86 |
| `rv64`、`riscv64` | 64 位 RISC-V |
| `rv32`、`riscv32` | 32 位 RISC-V |
| `spv`、`spirv` | SPIR-V 1.6 模块 |

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

CLI 也可以直接创建可构建的 Windows 与 Linux 起始项目。[格式教程](document/zh/format-tutorial.md)
提供完整的 PE、COFF 与 ELF 工作流。

## 编辑器支持

独立的 [XIRASM VS Code 扩展](https://codeberg.org/kukuyun/xirasm-vscode)
提供语法高亮、补全、导航与编译器诊断。

## 文档

- [完整中文文档 PDF](document/zh/pdf/xirasm-documentation-zh-CN.pdf) - 合并语言指南、
  格式教程与语言 API 参考，适合离线阅读。
- [中文语言指南](document/zh/language.md) - 学习编译期语言与汇编模型。
- [中文格式教程](document/zh/format-tutorial.md) - 按模板快速上手 PE、COFF
  和 ELF 的高层封装接口。
- [中文语言 API 参考](document/zh/api-reference.md) - 查询语法与内置 API。
- [高级格式构造指南（英文）](document/advanced-formats.md) - 需要手动控制时使用直接
  格式辅助接口。

## 状态

当前版本：**0.2.15**

XIRASM 仍处于 1.0 之前：汇编器、语言 API、格式库、CLI 与编辑器集成已经可以实际
使用，但公开契约在 1.0 前仍可能继续收敛。

## 许可证

Apache-2.0。
