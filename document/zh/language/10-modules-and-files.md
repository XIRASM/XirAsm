# 第 10 章：模块与文件

汇编项目通常很快就会超出单个源文件的规模。指令辅助函数、二进制记录定义、生成的表格、配置和嵌入数据往往由不同部分负责，也会因为不同原因发生变化。

XIRASM 提供两套彼此独立的文件加载方式：

- `include` 和 `import` 加载 XIRASM 源代码；
- `fs`、`json` 和 `toml` 函数加载供编译期代码使用的数据。

明确区分这两种用途，可以让项目更容易理解。源文件提供声明或输出操作；数据文件产生可以由源代码检查、转换和写出的值。

## 导入源代码模块

`import(path)` 对同一个源文件最多求值一次：

```asm
// 同一个模块导入两次，模块内容也只会求值一次。
import("support.inc");
import("support.inc");

emit_word(0x1234);
```

假设 `support.inc` 包含：

```text
fn emit_word(value: u64) {
    emit.u16(value);
}
```

两次导入最终指向同一个文件，因此函数只声明一次。示例会写出：

```text
34 12
```

定义可复用函数、常量、结构体或其他名称的文件应使用 `import`。即使多个依赖路径都导入同一模块，也不会重复它的声明或输出操作。

`import` 语句必须位于源文件顶层，不能放进局部执行会让模块加载变成条件行为的代码块：

```text
if target.bits == 64 {
    import("x64-support.inc");
}
```

需要选择模块时，应在源文件顶层完成；与目标平台相关的行为则放进模块内部。

## 在当前位置包含源代码

`include(path)` 每次执行到该语句时，都会重新求值指定的源文件：

```asm
// 同一个包含文件执行两次，因此其中的输出操作也执行两次。
include("inline.inc");
include("inline.inc");
```

如果 `inline.inc` 包含：

```text
emit.u8(0xaa);
```

输出为：

```text
aa aa
```

只有确实需要重复执行时才使用 `include`。常见用途包括：

- 在当前输出位置插入生成的数据；
- 共享一小段写出数据的语句；
- 从计算得到的路径选择源代码片段；
- 多次应用同一个源代码模板。

由于包含操作会重复执行，同一个文件如果重复声明函数、常量或类型，可能产生名称重复错误。这类文件通常属于模块，应改用 `import` 加载。

## 源代码路径如何解析

相对源代码路径以包含 `include` 或 `import` 语句的文件所在目录为起点进行解析。

假设项目结构如下：

```text
project/
    main.asm
    tables/
        records.inc
        shared/
            constants.inc
```

`tables/records.inc` 可以这样加载旁边 `shared` 子目录中的文件：

```text
import("shared/constants.inc");
```

这个路径相对于 `records.inc`，不一定相对于进程的工作目录，也不一定相对于最初的入口源文件。

如果在当前源文件旁边找不到相对路径指向的文件，XIRASM 会继续检查项目的 `include` 目录，然后检查安装位置的包含目录。这样，项目可以覆盖或补充已经安装的库，而不必在源代码中写入特定机器的绝对路径。

XIRASM 也接受绝对路径，但可移植项目通常应使用相对于源文件的路径，或使用已经配置的包含目录。

源代码加载不能形成循环。如果一个文件正在求值，它就不能直接或间接再次包含或导入自身。

## 选择 `import` 还是 `include`

应根据执行方式选择，而不是根据文件扩展名选择：

| 需要完成的工作 | 使用 |
|---|---|
| 只定义一次可复用名称 | `import` |
| 共享编译期函数或类型库 | `import` |
| 在当前输出位置执行源代码片段 | `include` |
| 多次执行同一个源文件 | `include` |
| 避免依赖链重复声明 | `import` |

一种实用的项目约定是：

- 模块定义可以复用的名称和操作；
- 包含片段完成与当前位置有关的工作；
- 入口源文件选择目标平台并汇编最终输出。

## 检查和读取数据文件

`fs.exists(path)` 检查是否能够解析指定的数据文件：

```asm
// 确认文件存在，再把它的全部字节写入输出。
assert(fs.exists("payload.bin"));
emit.bytes(fs.read_bytes("payload.bin"));
```

数据路径使用与源代码加载相同的相对路径规则。如果把这段代码移动到模块中，`payload.bin` 就会相对于该模块进行解析。

`fs.read_text(path)` 把整个文件读取为 `string`：

```asm
// 读取完整文本，检查内容后按原始字节写出。
const banner: string = fs.read_text("banner.txt");
assert(contains(banner, "XIRASM"));
emit.bytes(banner);
```

如果 `banner.txt` 包含：

```text
XIRASM
```

XIRASM 会写出文件中的精确字节，不会自动在末尾添加零字节。

`fs.read_bytes(path)` 把整个文件读取为 `bytes`。图像、已经编码的表格、预先生成的记录以及其他二进制载荷通常都适合使用这个函数。

## 读取一段字节

带三个参数的 `fs.read_bytes` 可以读取一个有明确边界的范围：

```asm
// 从偏移一开始读取两个字节。
const middle: bytes = fs.read_bytes("payload.bin", 1, 2);
assert(len(middle) == 2);
emit.bytes(middle);
```

第二个参数是从零开始计算的文件偏移，第三个参数是需要返回的字节数。

如果 `payload.bin` 包含：

```text
10 20 30 40
```

示例会写出：

```text
20 30
```

请求的完整范围必须存在。如果读取范围越过文件末尾，XIRASM 会报告错误，而不是悄悄缩短结果。

## 加载 JSON

`json.file(path)` 一次完成 JSON 文件的读取和解析：

```asm
// 读取配置，并从映射和列表中取出所需字段。
const config: map = json.file("config.json");
const values: list = map.get(config, "values");

assert(map.get(config, "enabled"));
emit.bytes(map.get(config, "name"));
emit.u8(map.get(config, "bits"));
emit.u8(list.get(values, 0));
emit.u8(list.get(values, 1));
```

输入文件如下：

```json
{
  "name": "XR",
  "bits": 64,
  "enabled": true,
  "values": [1, 2]
}
```

输出为：

```text
58 52 40 01 02
```

`json.parse(value)` 用来解析已经保存在 `string` 或 `bytes` 值中的 JSON：

```asm
// 先按文本读取文件，再显式解析其中的 JSON。
const raw: string = fs.read_text("config.json");
const config: map = json.parse(raw);
emit.u8(map.get(config, "bits"));
```

JSON 对象转换成映射，数组转换成列表，字符串和布尔值保持对应的编译期类型，非负整数转换成整数值。JSON 的 `null` 转换成 `void`。

当前编译期数据模型不支持浮点数和负整数，也会拒绝对象中的重复键和语法错误。

## 加载 TOML

`toml.file(path)` 为 TOML 提供相同的直接处理方式：

```asm
// 读取 TOML 配置，并从嵌套映射中取得目标宽度。
const config: map = toml.file("project.toml");
const target: map = map.get(config, "target");

emit.bytes(map.get(config, "name"));
emit.u8(map.get(target, "bits"));
```

输入文件如下：

```toml
name = "XR"

[target]
bits = 64
```

输出为：

```text
58 52 40
```

`toml.parse(value)` 用来解析保存在 `string` 或 `bytes` 值中的 TOML：

```asm
// 先读取原始文本，再显式解析 TOML。
const raw: string = fs.read_text("project.toml");
const config: map = toml.parse(raw);
const target: map = map.get(config, "target");

assert(map.get(target, "bits") == 64);
emit.u8(0x40);
```

TOML 表转换成映射，数组转换成列表，字符串、布尔值和非负整数转换成对应的编译期值。当前数据转换不接受浮点值和时间戳值。

## 分开管理配置和二进制载荷

结构化配置和原始二进制数据解决的是不同问题。

在这些情况下使用 JSON 或 TOML：

- 字段需要通过名称访问；
- 输入文件需要由用户直接编辑；
- 同一份输入用于生成多个值；
- 需要检查输入并根据条件生成内容。

在这些情况下使用 `fs.read_bytes`：

- 文件内容本身就是所需的二进制表示；
- 必须逐字节保持原样；
- 只需要文件中一个有明确边界的范围；
- 解析不会提供有用的结构。

如果文本本身就是载荷，或希望明确选择后续解析方式，则使用 `fs.read_text`。

## 实用的模块组织方式

中等规模的项目可以采用下面的结构：

```text
project/
    main.asm
    include/
        records.inc
        encoding.inc
    data/
        config.toml
        payload.bin
```

`main.asm` 导入可复用定义：

```text
import("records.inc");
import("encoding.inc");
```

这些模块可以读取相对于自身的数据，也可以使用 `../data/config.toml` 这样的明确相对路径。

应当让模块行为保持清晰：

- 声明库优先使用 `import`；
- 只有明确需要重复执行时才多次调用 `include`；
- 文件路径相对于负责使用它的源文件；
- 使用 `assert` 和 `fs.exists` 检查必要数据；
- 结构化文件只解析一次，并复用得到的映射或列表；
- 如果只需要大型文件的一部分，就使用有边界的二进制读取。

下一章将介绍输出区域和虚拟数据，说明 XIRASM 如何区分逻辑地址、文件中的实际字节、预留空间和临时布局区域。

[返回语言指南](../language.md)
