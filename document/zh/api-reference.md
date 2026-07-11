# XIRASM 语言 API 参考

本参考手册集中说明 XIRASM 的语法形式和内置 API，适合在已经了解基本概念后快速查找准确规则。需要按学习顺序理解语言特性时，请先阅读[语言指南](language.md)。

可执行文件与目标文件格式使用单独的文档：

- [可执行文件格式指南](formats.md)介绍常用的 PE、COFF 和 ELF 构建流程；
- 直接控制文件头、数据表、输出区域和重定位的底层接口属于高级格式指南。

本参考手册不收录 `format_*` 过程和格式系列专用辅助接口。

## 阅读约定

语法形式使用以下记号：

- `name` 表示由程序提供的标识符；
- `expression` 表示该位置允许使用的任意表达式；
- `type` 表示可选的显式类型；
- 语法形式中方括号内的内容可以省略。

除非另有说明，示例使用 x86-64 处理器指令。编译期语言规则不依赖所选指令集。

## 内容结构

### 第一部分：核心语言

1. **[源码、绑定与作用域](api-reference/01-source-bindings-and-scope.md)**
   - 标号、处理器指令、常量、变量、赋值、代码块和跨行参数。
2. **[函数与流程控制](api-reference/02-functions-and-control-flow.md)**
3. **[结构体、联合体与复合值](api-reference/03-structs-unions-and-aggregate-values.md)**
4. **[收尾处理语法形式](api-reference/04-finalization-forms.md)**

### 第二部分：汇编器操作

5. **[模块与诊断信息](api-reference/05-modules-and-diagnostics.md)**
6. **[目标平台、处理器指令与符号](api-reference/06-targets-isa-text-and-symbols.md)**
7. **[数据写出、预留空间与对齐](api-reference/07-emission-reservation-and-alignment.md)**
8. **[输出区域、输出区与游标](api-reference/08-regions-output-areas-and-cursors.md)**
9. **[读取、写入与最终区域信息](api-reference/09-loads-stores-and-final-region-facts.md)**

### 第三部分：编译期辅助库

10. **[文本、转换与标号名称](api-reference/10-text-conversion-and-symbol-names.md)**
11. **[字节序列](api-reference/11-byte-sequences.md)**
12. **[列表与映射](api-reference/12-lists-and-maps.md)**
13. **[文件与结构化数据](api-reference/13-files-and-structured-data.md)**
14. **[词法单元与模式匹配](api-reference/14-tokens-and-pattern-matching.md)**

每章保持紧凑的速查结构：先列出语法或函数形式，再说明行为、限制、错误条件和最小示例。
