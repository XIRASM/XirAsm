# XIRASM 可执行文件格式指南

处理器指令序列只是可执行文件的一部分。操作系统加载器和本机链接器还需要按照特定文件格式组织文件头、节或段、访问权限、符号、导入、导出和重定位信息。

XIRASM 提供常用格式接口，让普通汇编源代码可以直接构造这些文件：

```asm
// 导入面向普通程序的常用格式接口。
import("format/format.inc");
```

本指南通过完整的 PE、COFF 和 ELF 构建流程介绍这些接口。内容先讲解所有格式共用的模型，再分别说明各个格式系列。更底层、面向特殊格式实现的辅助接口不属于本指南，将在高级格式指南中单独介绍。

如果需要了解值、函数、标号、数据写出、输出区域或收尾处理的一般规则，请先阅读[语言指南](language.md)。如果希望由 XIRASM 生成可以直接构建的初始项目，请参见第 1 章的[从命令行开始](formats/01-introducing-executable-formats.md#从命令行开始)一节。

## 指南结构

### 第一部分：格式基础

1. **[认识 XIRASM 可执行文件格式](formats/01-introducing-executable-formats.md)**
   - 常用格式接口、第一个可执行文件，以及统一的格式构建流程。
2. **[格式方案与构建流程](formats/02-format-plans-and-lifecycle.md)**
   - 声明文件映像、写入命名内容、绑定入口并完成格式。
3. **[节、段、权限与未初始化数据区](formats/03-sections-segments-permissions-and-bss.md)**
   - 运行时映射、文件中有实际字节的数据、预留内存和对齐。
4. **[地址、符号与重定位](formats/04-addresses-symbols-and-relocations.md)**
   - 虚拟地址、相对虚拟地址、文件偏移、导入、导出和重定位信息。

### 第二部分：Windows 格式

5. **[PE32 与 PE64 可执行文件](formats/05-pe32-and-pe64-executables.md)**
   - 控制台程序、多节布局、数据、未初始化数据区和入口地址。
6. **[导入 Windows 接口函数](formats/06-importing-windows-apis.md)**
   - 导入声明、自动生成的数据表和外部函数调用。
7. **[动态链接库导出与基址重定位](formats/07-dll-exports-and-base-relocations.md)**
   - 导出函数和数据、重定位声明与地址随机化策略。
8. **[PE 资源与校验和](formats/08-pe-resources-and-checksums.md)**
   - 资源数据、资源文件和可选的映像校验和。
9. **[COFF32 与 COFF64 目标文件](formats/09-coff32-and-coff64-objects.md)**
   - 节、公开符号、外部符号、重定位和本机链接。

### 第三部分：ELF 格式

10. **[ELF32 与 ELF64 可执行文件](formats/10-elf32-and-elf64-executables.md)**
    - 可加载段、紧凑的文件布局、数据、未初始化数据区和入口地址。
11. **[位置无关可执行文件与动态导入](formats/11-position-independent-executables-and-dynamic-imports.md)**
    - 位置无关映像、动态元数据、过程链接表调用和外部函数。
12. **[ELF32 与 ELF64 目标文件](formats/12-elf32-and-elf64-object-files.md)**
    - 节、符号、`REL` 与 `RELA` 两种重定位记录形式，以及本机链接。
13. **[ELF64 共享对象](formats/13-elf64-shared-objects.md)**
    - 导出符号、导入符号、加载方式和其他语言调用者。

本指南只介绍常用格式接口。直接构造格式数据表和使用格式专用的底层辅助接口，属于独立的高级格式指南，以免普通构建流程被实现细节淹没。
