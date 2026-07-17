// XIRASM 标准库最小核心层总入口。
//
// 当前实验版本公开 x86-64 memory、CPU feature 与 runtime dispatch 原语。
// 导入本文件只声明 Meta/DSL 生成函数，不会立刻写入运行时代码；调用方需要
// 在可执行文本区域中显式调用对应 emitter 来生成实际入口。

import("core/memory.inc");
import("core/cpu.inc");
import("core/dispatch.inc");
