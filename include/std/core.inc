// XIRASM 标准库最小核心层总入口。
//
// 当前实验版本只公开 x86-64 memory 原语。导入本文件只声明 Meta/DSL
// 生成函数，不会立刻写入运行时代码；调用方需要在可执行文本区域中调用
// std_memory_emit(...) 一次来生成实际入口。

import("core/memory.inc");
