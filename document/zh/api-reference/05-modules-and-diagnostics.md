# 第 5 章：模块与诊断信息

## 语法摘要

| API | 语法 | 结果 |
| --- | --- | --- |
| 包含源码 | `include(path)` | 每次调用都执行解析后的源码。 |
| 导入源码 | `import(path)` | 解析后的源码只执行一次。 |
| 提示 | `print(value, ...)` | 记录不会终止汇编的提示信息。 |
| 警告 | `warn(value, ...)` | 记录不会终止汇编的警告信息。 |
| 错误 | `err(value, ...)` | 记录错误并停止汇编。 |
| 断言 | `assert(condition[, message])` | 条件为假时停止汇编。 |

## 源码路径

传给 `include` 和 `import` 的 `path` 参数必须求值得到文本。相对路径从包含该调用的源文件所在位置开始解析，因此一个被加载的文件可以继续按自己的目录加载其他文件。

解析后的源码路径同时也是模块标识。两种不同写法只要解析到同一个源文件，就表示同一次导入。

## 重复包含源码

每次调用 `include(path)` 都会执行被加载的源码：

```text
include("row.inc")
include("row.inc")
```

如果 `row.inc` 写出一个字节，这个字节就会写出两次。重复包含也会重复执行声明，因此多次包含声明了同一个函数或类型的文件，可能产生重复声明错误。

需要有意重复展开源码时，或者源码片段中的声明能够安全地在每个调用位置执行时，可以使用 `include`。

## 模块只导入一次

`import(path)` 只在第一次导入时执行被加载的源码：

```text
import("library.inc")
import("library.inc")
```

第二次调用不会产生任何效果。因此，定义函数、类型、常量或可复用数据的文件通常应使用 `import`。

导入是模块顶层操作。在词法作用域的代码块或函数内部调用 `import` 是无效的。遇到递归的包含或导入链时，汇编器会拒绝整个循环，而不会只执行其中一部分。

## 诊断信息

`print`、`warn` 和 `err` 可以接收一个或多个值：

```asm
// 设置逻辑原点，再记录当前位置、警告和断言信息。
origin(0)

print("offset", here())
warn("diagnostic example", true)
assert(here() == 0, "unexpected origin")

// 写出一个字节，证明提示和警告不会停止汇编。
emit.u8(0x5a)
```

各个值会使用常规文本形式格式化，并以一个空格连接。上面的示例会记录：

```text
note: offset 0
warning: diagnostic example true
```

`print` 和 `warn` 不会停止汇编。`err` 会在调用位置记录错误并停止汇编：

```text
err("unsupported width", 24)
```

诊断 API 也可以在 `defer` 收尾块中使用。模块加载 API 不能在收尾处理中调用。

## 断言

`assert` 接收一个布尔条件和一条可选消息：

```asm
// 检查位宽是否有效，再把对应的字节数写入输出内容。
const width = 64
assert(width == 64)
assert(width % 8 == 0, "width must use whole bytes")

emit.u8(width / 8)
```

条件为真时，`assert` 不会写出内容，也不会记录诊断信息。条件为假时，汇编会停止并显示提供的消息。省略消息时，诊断文本为 `assertion failed`。

## 完整模块示例

下面四个文件共同演示重复包含、只导入一次、嵌套相对路径和诊断信息。

`main.asm`：

```text
origin(0)

include("repeat.inc")
include("repeat.inc")

import("module/once.inc")
import("module/once.inc")

print("module bytes", here())
warn("diagnostic example", true)
assert(here() == 4, "unexpected module output")

emit.u8(0x44)
```

`repeat.inc`：

```text
emit.u8(0x11)
```

`module/once.inc`：

```text
include("nested.inc")
emit.u8(0x22)
```

`module/nested.inc`：

```text
emit.u8(0x33)
```

最终输出为：

```text
11 11 33 22 44
```

`repeat.inc` 会执行两次。`module/once.inc` 只执行一次，其中嵌套的 `include` 会相对于 `module` 目录解析路径。
