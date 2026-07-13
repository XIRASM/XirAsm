# 第 13 章：文件与结构化数据

## 语法摘要

| 函数 | 结果 | 说明 |
| --- | --- | --- |
| `fs.exists(path)` | `bool` | 检查指定路径能否定位到文件。 |
| `fs.read_text(path)` | `string` | 把整个文件读取为字符串。 |
| `fs.read_bytes(path)` | `bytes` | 把整个文件读取为字节序列。 |
| `fs.read_bytes(path, offset, count)` | `bytes` | 读取一段长度明确的字节范围。 |
| `emit.file(path)` | 语句 | 写出完整的源文件相对文件。 |
| `emit.file(path, offset, count)` | 语句 | 写出精确的文件字节范围。 |
| `json.parse(value)` | 值 | 解析字符串或字节序列中的 JSON。 |
| `json.file(path)` | 值 | 读取并解析 JSON 文件。 |
| `toml.parse(value)` | `map` | 解析字符串或字节序列中的 TOML 文档。 |
| `toml.file(path)` | `map` | 读取并解析 TOML 文件。 |

文件路径遵循与 `include` 和 `import` 相同的受控路径规则。相对路径以包含该调用的源文件为基准。因此，把调用移动到嵌套模块中时，它所使用的相对数据路径基准也会随之改变。

## 各阶段的可用性

| 操作 | 常规求值阶段 | `late_layout` | `defer` |
| --- | --- | --- | --- |
| `fs.exists`、`fs.read_text`、`fs.read_bytes`、`emit.file` | 可用 | 不可用 | 不可用 |
| `json.file`、`toml.file` | 可用 | 不可用 | 不可用 |
| `json.parse`、`toml.parse` | 可用 | 可在值表达式中使用 | 可在值表达式中使用 |

文件操作需要当前阶段能够按照源文件位置解析路径。`late_layout` 和 `defer` 阶段不能重新访问源文件。需要在后期使用结构化数据时，应当在常规求值阶段完成文件读取与解析，并保留得到的值。

`parse` 函数不访问文件系统，只处理传入的字符串或字节序列。

## 检查与读取文件

路径无法定位到文件时，`fs.exists` 返回 `false`。读取函数遇到缺失文件时则会报告错误。

`fs.read_text` 保留文件的完整内容，不会附加结尾零字节。`fs.read_bytes` 返回内容相同的字节序列。

```asm
// 先检查必需文件与可选文件是否存在。
assert(fs.exists("payload.bin"))
assert(fs.exists("banner.txt"))
assert(!fs.exists("optional.bin"))

// 从二进制文件读取四字节文件头，并把文本文件读取为字符串。
const header: bytes = fs.read_bytes("payload.bin", 0, 4)
const banner: string = fs.read_text("banner.txt")

// 按读取顺序写出二进制文件头和文本内容。
emit.bytes(header)
emit.bytes(banner)
```

如果 `payload.bin` 包含 `XIR!`，而 `banner.txt` 包含 `ready` 和紧随其后的换行符，示例会写出：

```text
58 49 52 21 72 65 61 64 79 0a
```

范围读取形式使用从零开始的偏移和字节数量。整个范围必须位于文件以内。在文件末尾读取长度为零的范围是有效操作。

`emit.file` 使用与 `fs.read_bytes` 完全相同的解析器和范围规则，但会直接写入输出，而不是返回 `bytes` 值。

## JSON 值

JSON 值按下表转换为编译期值：

| JSON 值 | 编译期值 |
| --- | --- |
| `null` | `void` |
| 布尔值 | `bool` |
| 字符串 | `string` |
| 非负整数 | 整数 |
| 数组 | `list` |
| 对象 | `map` |

`json.file` 在一次调用中完成读取和解析。`json.parse` 接受已经包含 JSON 内容的字符串或字节序列。

```asm
// 分别直接读取配置文件，以及读取字节后再次解析同一份配置。
const config: map = json.file("config.json")
const parsed_again: map = json.parse(fs.read_bytes("config.json"))
const values: list = map.get(config, "values")

// 两种读取方式应得到相同映射，值为 null 的键也仍然存在。
assert(map.eq(config, parsed_again))
assert(map.get(config, "enabled"))
assert(map.has(config, "nothing"))

// 从映射中读取文本、整数和列表，并按配置内容写出字节。
emit.bytes(map.get(config, "name"))
emit.u8(map.get(config, "bits"))

for value in values {
    emit.u8(value)
}
```

对应输入为：

```json
{
  "name": "XR",
  "bits": 64,
  "enabled": true,
  "values": [1, 2],
  "nothing": null
}
```

示例会写出 `58 52 40 01 02`。

JSON 浮点数、负整数、重复的对象键、格式错误的输入，以及超出支持范围的整数都会被拒绝。

## TOML 值

TOML 文档转换为映射。嵌套表转换为嵌套映射，数组转换为列表，字符串、布尔值和非负整数保持对应的编译期值类型。

```asm
// 分别直接读取配置文件，以及读取文本后再次解析同一份配置。
const config: map = toml.file("config.toml")
const parsed_again: map = toml.parse(fs.read_text("config.toml"))
const target: map = map.get(config, "target")
const values: list = map.get(parsed_again, "values")

// 两种读取方式应得到相同映射，并保留布尔配置。
assert(map.eq(config, parsed_again))
assert(map.get(config, "enabled"))

// 从顶层映射和嵌套映射中读取输出字段。
emit.bytes(map.get(config, "name"))
emit.u8(map.get(target, "bits"))

for value in values {
    emit.u8(value)
}
```

对应输入为：

```toml
# 顶层配置值。
name = "XR"
enabled = true
values = [3, 4]

# 目标平台配置表。
[target]
bits = 32
```

示例会写出 `58 52 20 03 04`。

浮点数、时间戳、负整数、格式错误的文档和重复键都会在转换过程中被拒绝。

## 错误条件

以下情况会被这些辅助接口拒绝：

- 文件路径不是字符串；
- 传给读取函数或 `*.file` 函数的文件不存在；
- 字节范围超出文件边界；
- 传给 `json.parse` 或 `toml.parse` 的值既不是字符串，也不是字节序列；
- JSON 或 TOML 格式错误；
- 对象或表中存在重复键；
- 结构化数据包含无法表示为编译期值的内容；
- 函数实参数量不正确。

只有文件缺失属于预期情况时，才需要在读取前调用 `fs.exists`。
