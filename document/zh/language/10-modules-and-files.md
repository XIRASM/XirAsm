# 第 10 章：模块与文件

汇编项目很快就会超过单个源文件的规模。指令辅助函数、二进制记录定义、生成的表格、配置数据和嵌入数据，通常由不同的人维护，变更原因也各异。

XIRASM 提供两种独立的文件加载模型：

- `include` 和 `import` 加载 XIRASM 源文件；
- `fs`、`json` 和 `toml` 函数加载 Meta 代码使用的数据。

区分这两种角色可以让项目结构更清晰：源文件提供声明或执行输出操作；数据文件被读取后变成源码可以检查、转换和写出的值。

本章只讲汇编期间读取文件，也就是 `fs.*`、`json.*` 和 `toml.*` 这些编译期接口。最终程序运行时怎样读写文件，属于操作系统 ABI、系统调用或运行时库的问题，不在本章范围内。

## 导入源模块

`import(path)` 对给定的源文件至多求值一次：

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

两次导入指向同一个已解析文件，因此函数只声明一次。示例输出：

```text
34 12
```

定义可复用函数、常量、结构体或其他名字的文件应使用 `import`。即使通过多条依赖路径引入同一模块，其声明和输出也不会重复。

`import` 语句必须位于源文件顶层，不可放置于可能按条件执行的块中：

```text
if target.bits == 64 {
    import("x64-support.inc");
}
```

应在顶层选择要导入的模块；如果行为取决于目标，就把目标判断写在模块内部。

## 内联包含源文件

`include(path)` 每执行到一次就对目标源文件重新求值：

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

仅在确实需要重复执行时使用 `include`。典型用途包括：

- 在当前输出位置插入生成的数据；
- 共享一段短的写出语句序列；
- 从计算得出的路径选取源文件片段；
- 多次应用同一个源文件模板。

由于包含操作重复执行，多次包含一个声明了相同函数、常量或类型的文件可能导致重名错误。这类文件通常是模块，应通过 `import` 加载。

## 源文件路径解析

相对路径以包含 `include` 或 `import` 语句的文件所在目录为基准进行解析。

对于以下项目：

```text
project/
    main.asm
    tables/
        records.inc
        shared/
            constants.inc
```

`tables/records.inc` 可以加载相邻文件：

```text
import("shared/constants.inc");
```

该路径相对于 `records.inc`，而非进程工作目录或入口源文件。

如果在当前源文件旁未找到相对路径对应的文件，XIRASM 会依次检查项目的 `include` 目录及其安装目录下的 include 目录。这使项目模块能够覆盖或补充已安装的库，而无需在源码中写入本机绝对路径。

绝对路径也可使用，但可移植的项目应优先使用相对于源文件的路径或已配置的 include 根目录。

源文件加载不允许形成循环。一个文件正在求值期间，不得直接或间接地再次包含或导入自身。

## 选择 `import` 还是 `include`

应根据执行语义选择，而非文件扩展名：

| 需求 | 使用 |
| --- | --- |
| 仅声明一次可复用名字 | `import` |
| 共享 Meta 函数或类型库 | `import` |
| 在当前输出位置执行源文件片段 | `include` |
| 重复执行同一源文件 | `include` |
| 避免依赖链中的重复声明 | `import` |

项目约定的常见做法：

- 模块定义可复用的名字和类型；
- 包含的片段执行与输出位置相关的工作；
- 入口源文件选择目标并组装最终输出。

## 检查与读取数据文件

`fs.exists(path)` 检查数据文件是否能按当前路径规则找到：

```asm
// 确认文件存在，再把它的全部字节写入输出。
assert(fs.exists("payload.bin"));
emit.bytes(fs.read_bytes("payload.bin"));
```

数据路径使用与源文件加载相同的相对路径解析模型。当这段代码移入模块时，`payload.bin` 会相对于该模块所在文件解析。

`fs.read_text(path)` 将整个文件读为 `string`：

```asm
const banner: string = fs.read_text("banner.txt")
assert(contains(banner, "XIRASM"));
emit.bytes(banner);
```

如果 `banner.txt` 包含：

```text
XIRASM
```

按原样写出文件中的字节，不会自动追加终止零字节。

`fs.read_bytes(path)` 将整个文件读为 `bytes`。图片、编码后的表格、预构建的记录及其他二进制数据均适用。

当字节仅用于输出时，`emit.file(path)` 可避免创建中间绑定。`emit.file(path, offset, count)` 写出精确的范围。这两种形式均使用与 `fs.read_bytes` 相同的相对路径解析器和边界检查，但不能在 `late_layout` 和 `defer` 中使用。

## 读取字节范围

三参数形式的 `fs.read_bytes` 读取带边界的范围：

```asm
const middle: bytes = fs.read_bytes("payload.bin", 1, 2)
assert(len(middle) == 2);
emit.bytes(middle);
```

第二个参数是基于零的文件偏移，第三个参数是返回的字节数。

如果 `payload.bin` 包含：

```text
10 20 30 40
```

示例输出：

```text
20 30
```

所请求的范围必须完整存在。XIRASM 会报告越界读取错误，而非静默截断。

## 加载 JSON

`json.file(path)` 一次性完成 JSON 文件的读取和解析：

```asm
const config: map = json.file("config.json")
const values: list = map.get(config, "values")

assert(map.get(config, "enabled"));
emit.bytes(map.get(config, "name"));
emit.u8(map.get(config, "bits"));
emit.u8(list.get(values, 0));
emit.u8(list.get(values, 1));
```

对于以下输入：

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

`json.parse(value)` 解析已包含在 `string` 或 `bytes` 值中的 JSON：

```asm
const raw: string = fs.read_text("config.json")
const config: map = json.parse(raw)
emit.u8(map.get(config, "bits"));
```

JSON 对象转换为 map，数组转换为 list，字符串和布尔值保持相应的 Meta 类型，非负整数转换为整数值。JSON 的 `null` 转换为 `void`。

浮点数和负整数不在当前 Meta 数据模型的范围内。重复的键和格式错误的 JSON 将被拒绝。

## 加载 TOML

`toml.file(path)` 为 TOML 提供同样的便捷入口：

```asm
const config: map = toml.file("project.toml")
const target: map = map.get(config, "target")

emit.bytes(map.get(config, "name"));
emit.u8(map.get(target, "bits"));
```

对于以下输入：

```toml
name = "XR"

[target]
bits = 64
```

输出为：

```text
58 52 40
```

`toml.parse(value)` 从 `string` 或 `bytes` 值中解析 TOML：

```asm
const raw: string = fs.read_text("project.toml")
const config: map = toml.parse(raw)
const target: map = map.get(config, "target")

assert(map.get(target, "bits") == 64);
emit.u8(0x40);
```

TOML 表转换为 map，数组转换为 list，字符串、布尔值和非负整数转换为相应的 Meta 值。Meta 数据转换目前不接受浮点数和时间戳值。

## 区分配置与二进制数据

结构化配置和原始二进制数据解决不同的问题。

使用 JSON 或 TOML 的场景：

- 字段需通过名称访问；
- 输入预期由人工编辑；
- 同一输入驱动多个生成值；
- 需进行校验和条件生成。

使用 `fs.read_bytes` 的场景：

- 文件内容已是所需的二进制表示；
- 需保持字节级的精确性；
- 仅需有限的字节范围；
- 解析不会带来有用的结构。

当文本本身就是数据，或需显式应用某个解析器时，使用 `fs.read_text`。

## 实用的模块组织方式

中等规模的项目可采用以下结构：

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

`main.asm` 导入可复用的定义：

```text
import("records.inc");
import("encoding.inc");
```

这些模块可以相对于自身读取数据，或通过显式路径（如 `../data/config.toml`）读取。

应保持模块行为的可读性：

- 声明库优先使用 `import`；
- `include` 仅用于确实需要重复执行的工作；
- 文件路径相对于所属源文件书写；
- 用 `assert` 和 `fs.exists` 验证必要数据；
- 结构化文件仅解析一次，复用得到的 map 或 list；
- 大型文件仅需部分内容时，使用有界的二进制读取。

下一章介绍输出区域与虚拟数据：XIRASM 如何分离逻辑地址 / RVA、raw 文件偏移 / FOA、尾部 reserve 和临时虚拟输出。

[返回目录](../language.md)
