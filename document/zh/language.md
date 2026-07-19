# XIRASM 语言指南

XIRASM 是一款面向 x86、RISC-V 和 SPIR-V 的汇编器。处理器指令按熟悉的汇编语法直接写；需要在汇编期间计算、选择、循环生成或组织文件格式时，再使用 XIRASM 的编译期语言。

本指南按学习顺序讲：先看一份最小源文件，再学值、表达式、控制流、函数和集合；之后进入标号、数据布局、输出区域与收尾处理；最后说明 flat binary、自定义格式以及 PE/COFF/ELF 文件从哪里开始。查函数签名时看[语言 API 参考](api-reference.md)；照着写 PE、COFF 或 ELF 文件时看[格式教程](format-tutorial.md)。

## 指南结构

### 第一部分：语言基础

1. **[认识 XIRASM](language/01-introducing-xirasm.md)**
   - 汇编第一个 x86-64 程序。
   - 理解指令行与编译期代码如何配合。
   - 看懂最小源文件的语法规则。
2. **[值与绑定](language/02-values-and-bindings.md)**
   - 声明常量和可变的局部绑定。
   - 使用整数、布尔值、字符串和字节。
   - 理解作用域和赋值。
3. **[表达式](language/03-expressions.md)**
   - 使用算术、比较、逻辑、位运算和字段表达式。
   - 调用函数并组合编译期计算。
4. **[控制流](language/04-control-flow.md)**
   - 使用 `if` 选择需要生成的内容。
   - 使用 `while` 和 `for` 重复执行操作。
   - 根据编译期条件生成数据和指令。
5. **[函数与作用域](language/05-functions-and-scope.md)**
   - 编写不返回值的过程和返回值的函数。
   - 使用参数、返回类型、局部绑定和嵌套作用域。
6. **[集合与文本](language/06-collections-and-text.md)**
   - 创建和处理列表、映射、字符串及字节序列。
   - 使用集合描述表格和需要生成的输出内容。
7. **[词法单元与模式匹配](language/07-tokens-and-pattern-matching.md)**
   - 检查词法单元序列。
   - 匹配类似源码的文本，用来写小型 DSL 或生成辅助工具。

### 第二部分：汇编器模型

8. **[目标、指令与标号](language/08-targets-isa-text-and-labels.md)**
   - 选择指令集和指令模式。
   - 定义标号，并在指令中使用编译期值。
   - 理解地址引用与回填。
9. **[数据与二进制布局](language/09-data-and-binary-layout.md)**
   - 写出整数、字符串和字节。
   - 预留空间并控制对齐方式。
   - 定义具有精确二进制布局的结构体和联合体。
10. **[模块与文件](language/10-modules-and-files.md)**
    - 通过包含和导入复用源代码。
    - 从普通文件以及 JSON、TOML 格式中读取源数据。
11. **[输出区域与虚拟数据](language/11-output-regions-and-virtual-data.md)**
    - 区分逻辑地址 / RVA、raw 文件偏移 / FOA 和最终进入文件的字节。
    - 构建输出区域，区分 raw 文件间隙和只增加逻辑大小的尾部 reserve。
    - 使用虚拟输出作为临时组装、测量和转换区域。
12. **[收尾处理](language/12-finalizers.md)**
    - 等布局稳定后再执行检查和回填。
    - 计算校验和与最终字段值。
    - 理解哪些操作不得改变最终布局。

### 第三部分：构建程序

13. **[Flat Binary 与自定义格式](language/13-flat-and-custom-binaries.md)**
    - 构建紧凑的 flat binary 和项目专用文件格式。
    - 用标号、区域、`defer` 和 `late_layout` 推导文件头字段。
14. **[可执行文件与目标文件格式](language/14-executable-and-object-formats.md)**
    - 理解 `format.inc` 会替你生成哪些格式结构。
    - 使用 `let` 和 `_mut` 函数构建最小可执行文件。
    - 通过格式教程继续学习 PE、COFF、ELF、导入、导出、BSS（未初始化数据区）和重定位。
15. **[诊断信息与实用约定](language/15-diagnostics-and-practical-conventions.md)**
    - 报告无效输入，并检查布局是否符合预期。
    - 组织可复用的汇编项目。
    - 在掌握本指南后继续查阅接口参考和格式教程。
