# 第 10 章：模块与文件

汇编项目很快就会超过单个源文件的规模。指令辅助函数、二进制记录定义、生成的表格、配置数据和嵌入数据，常常由不同的人维护，变更原因也各异。

XIRASM 分两条路加载外部文件：

- `include` 和 `import` 加载 XIRASM 源文件；
- `fs`、`json` 和 `toml` 加载 Meta 代码要用的数据。

分开之后项目结构更清楚：源文件提供声明，或执行输出操作；数据文件被读进来，变成源码可以检查、转换和写出的值。

`fs.*`、`json.*` 和 `toml.*` 读的都是汇编期间的数据。最终程序运行时怎样读写文件，属于操作系统 ABI、系统调用或运行时库的问题，不在语言指南范围内。

## 导入源模块

`import(path)` 对给定的源文件至多求值一次：

```asm id=10-import
// 同一个模块导入两次，模块内容也只会求值一次。
import("support.inc")
import("support.inc")

emit_word(0x1234)
```

假设 `support.inc` 包含：

```text
fn emit_word(value: u64) {
    emit.u16(value)
}
```

两次导入指向同一个已解析文件，所以函数只声明一次。示例输出：

```text
34 12
```

定义可复用函数、常量、结构体或其他名字的文件用 `import`。即使通过多条依赖路径引入同一个模块，声明和输出也不会重复。

`import` 语句必须写在源文件顶层，不能放进可能按条件执行的块里：

```text
if target.bits == 64 {
    import("x64-support.inc")
}
```

要在顶层选择导入哪些模块；如果行为取决于目标，就把目标判断写进模块内部。

## 内联包含源文件

`include(path)` 每执行到一次，就对目标源文件重新求值：

```asm id=10-include
// 同一个包含文件执行两次，因此其中的输出操作也执行两次。
include("inline.inc")
include("inline.inc")
```

如果 `inline.inc` 包含：

```text
emit.u8(0xaa)
```

输出为：

```text
aa aa
```

`include` 只用在确实需要重复执行的地方：

- 在当前输出位置插入生成的数据；
- 共享一段短的写出语句序列；
- 从计算得出的路径选取源文件片段；
- 多次套用同一个源文件模板。

因为包含操作会重复执行，多次包含一个声明了相同函数、常量或类型的文件会报重名错误。这类文件属于模块，用 `import` 加载。

## 源文件路径解析

相对路径以包含 `include` 或 `import` 语句的那个文件所在目录为基准解析。

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
import("shared/constants.inc")
```

这个路径相对于 `records.inc`，而不是进程工作目录或入口源文件。

当前源文件旁找不到相对路径对应的文件时，XIRASM 依次检查项目的 `include` 目录及其安装目录下的 include 目录。项目模块因此可以覆盖或补充已安装的库，不必在源码里写本机绝对路径。

绝对路径也能用，但可移植的项目应优先使用相对于源文件的路径，或已配置的 include 根目录。

源文件加载不允许形成循环：一个文件正在求值期间，不得直接或间接地再次包含或导入自身。

## `import` 与 `include`

按实际执行方式自行选择，不看文件扩展名(都一样)：

| 需求                         | 使用        |
| ---------------------------- | ----------- |
| 仅声明一次可复用名字         | `import`  |
| 共享 Meta 函数或类型库       | `import`  |
| 在当前输出位置执行源文件片段 | `include` |
| 重复执行同一源文件           | `include` |
| 避免依赖链中的重复声明       | `import`  |

## 检查与读取数据文件

`fs.exists(path)` 检查数据文件是否能按当前路径规则找到：

```asm id=10-assert
// 确认文件存在，再把它的全部字节写入输出。
assert(fs.exists("payload.bin"))
emit.bytes(fs.read_bytes("payload.bin"))
```

数据路径使用与源文件加载相同的相对路径解析模型。这段代码移入模块后，`payload.bin` 相对于该模块所在文件解析。

`fs.read_text(path)` 把整个文件读成 `string`：

```asm id=10-read-text
const banner: string = fs.read_text("banner.txt")

// 读进来的是字符串，可以直接用字符串接口检查。
assert(contains(banner, "XIRASM"))

// 再交给写输出接口，原样进文件。
emit.bytes(banner)
```

如果 `banner.txt` 包含：

```text
XIRASM
```

写出的是文件里的原始字节，**不追加终止零字节，也不做换行转换**：文件最后一行的换行符照样写出去。

`fs.read_bytes(path)` 把整个文件读成 `bytes`，适用于图片、编码后的表格、预构建的记录及其他二进制数据。

字节只用于输出时，`emit.file(path)` 省掉中间绑定；`emit.file(path, offset, count)` 写出精确的范围。两者使用与 `fs.read_bytes` 相同的相对路径解析器和边界检查，但不能在 `late_layout` 和 `defer` 里使用。

## 列出目录

`fs.list_dir(path)` 返回目录中的条目名，`fs.is_dir(path)` 检查某个路径是否为目录：

```asm id=10-list-dir
// 把 assets 下的文件依次写进输出，子目录跳过。
for entry in fs.list_dir("assets") {
    if fs.is_dir(sym.join("assets/", entry)) {
        continue
    }
    emit.file(sym.join("assets/", entry))
}
```

列表里是条目名而不是路径，目录和文件一起出现；列表按字节升序排列，所以生成的映像不依赖宿主文件系统返回条目的顺序。这两个函数与上面的读取函数使用完全相同的路径解析规则。`fs.is_dir` 在路径无法定位时返回 `false`，所以适合作为"目录可有可无"时的判断依据。

## 读取字节范围

三参数形式的 `fs.read_bytes` 读取带边界的范围。第二个参数是基于零的文件偏移，第三个参数是要读的字节数：

```asm id=10-read-bytes bytes=2030
// 跳过第 0 个字节，从第 1 个字节起读 2 个字节。
const middle: bytes = fs.read_bytes("payload.bin", 1, 2)

assert(len(middle) == 2)
emit.bytes(middle)
```

`payload.bin` 里是 `10 20 30 40`，所以写出的是：

```text
20 30
```

所请求的范围必须完整存在。越界读取会报错，不会静默截断。

## 加载 JSON

`json.file(path)` 一次完成 JSON 文件的读取和解析：

```asm id=10-file
// 一次读入并解析：得到的是一个 map。
const config: map = json.file("config.json")
const values: list = map.get(config, "values")

// 布尔值可以直接当条件用。
assert(map.get(config, "enabled"))

emit.bytes(map.get(config, "name"))    // 字符串
emit.u8(map.get(config, "bits"))       // 整数
emit.u8(list.get(values, 0))           // 数组变成 list，按下标取
emit.u8(list.get(values, 1))
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

`json.parse(value)` 解析已经装在 `string` 或 `bytes` 值里的 JSON：

```asm id=10-read-text-2
// 自己读进来再解析：文件里装的必须是合法的 JSON。
const raw: string = fs.read_text("config.json")
const config: map = json.parse(raw)

emit.u8(map.get(config, "bits"))
```

JSON 对象转成 map，数组转成 list，字符串和布尔值保持相应的 Meta 类型，非负整数转成整数值，`null` 转成 `void`。

浮点数和负整数目前不在 Meta 数据模型内。重复的键和格式错误的 JSON 会被拒绝。

## 加载 TOML

`toml.file(path)` 是 TOML 的便捷入口：

```asm id=10-file-2
// TOML 的表（[target]）会变成嵌套的 map。
const config: map = toml.file("project.toml")
const target: map = map.get(config, "target")

emit.bytes(map.get(config, "name"))
emit.u8(map.get(target, "bits"))
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

```asm id=10-read-text-3
// 同样可以先读成文本，再交给 toml.parse。
const raw: string = fs.read_text("project.toml")
const config: map = toml.parse(raw)
const target: map = map.get(config, "target")

assert(map.get(target, "bits") == 64)
emit.u8(0x40)
```

TOML 表转成 map，数组转成 list，字符串、布尔值和非负整数转成相应的 Meta 值。Meta 数据转换目前不接受浮点数和时间戳。

## 配置数据与二进制数据

结构化配置和原始二进制数据解决的是不同问题。

| 情况                           | 使用              |
| ------------------------------ | ----------------- |
| 字段要按名称访问               | JSON 或 TOML      |
| 输入预期由人工编辑             | JSON 或 TOML      |
| 同一份输入要驱动多个生成值     | JSON 或 TOML      |
| 需要校验和条件生成             | JSON 或 TOML      |
| 文件内容已经是所需的二进制表示 | `fs.read_bytes` |
| 需要字节级精确                 | `fs.read_bytes` |
| 只需要有限的字节范围           | `fs.read_bytes` |
| 解析不会带来有用的结构         | `fs.read_bytes` |
| 文本本身就是数据               | `fs.read_text`  |
| 要显式应用某个解析器           | `fs.read_text`  |

## 模块组织

中等规模的项目可以这样组织：

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
import("records.inc")
import("encoding.inc")
```

这些模块可以相对于自身读取数据，也可以通过显式路径（如 `../data/config.toml`）读取。

模块行为保持可读的做法：

- 声明库用 `import`；
- `include` 只用于确实需要重复执行的工作；
- 文件路径相对于所属源文件书写；
- 用 `assert` 和 `fs.exists` 验证必要数据；
- 结构化文件只解析一次，复用得到的 map 或 list；
- 大型文件只需要部分内容时，用有界的二进制读取。

[返回目录](../language.md)
