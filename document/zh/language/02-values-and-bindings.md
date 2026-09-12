# 第 2 章：值与绑定

## 值只存在于汇编期间

XIRASM 的值都是编译期值。绑定只给值起名；只有指令、数据调用、布局操作或格式接口用到它时，它才进入输出。

```asm id=value-is-not-output target=x86-64 bytes=4d5a
const magic: u16 = 0x5a4d   // 给值起名，此时还没有写出任何字节
dw(magic)                   // 这一行才写出 `4d 5a`
```

## 常量

`const` 绑定一个不能重新赋值的名字：

```asm id=const-decl target=x86-64
const page_size: u64 = 4096   // 宽度是约定的一部分
const header_size = 64        // 由初始值推断
```

```text
const name = expression
const name: type = expression
```

初始值能决定类型时可以省略类型注解；宽度属于二进制约定时要写出类型。给 `const` 重新赋值是错误：

```asm id=const-reassign target=x86-64
const value = 1
value = 2
```

```text
bad.xir:2:1: error: the declaration syntax is not valid (InvalidValueDeclaration)
```

## 可变绑定

`let` 绑定的名字可以在汇编期间更新：

```asm id=mutable-offset target=x86-64 bytes=14000000
let offset: u32 = 0
offset = offset + 16   // 赋值在汇编期间执行
offset = offset + 4

dd(offset)             // 20 = 0x14
```

```text
let name = expression
let name: type = expression
name = expression
```

声明和赋值都是编译期工作，输出里没有对应的运行时变量。只在确实要更新这个名字时才用 `let`。

## 类型注解与类型推断

```asm id=type-annotations target=x86-64
const signature: u16 = 0x5a4d   // 显式写出：它是文件格式字段
const title: string = "XIRASM"
const marker: bytes = b"OK"
const enabled: bool = true

const count = 4                 // 推断为 `integer`
const name = "payload"          // 推断为 `string`
const raw = b"DATA"             // 推断为 `bytes`
```

常用的值类型：

| 类型 | 用途 | 示例 |
| --- | --- | --- |
| `integer` | 通用编译期整数 | `42` |
| `u8`、`u16`、`u32`、`u64` | 对应宽度的无符号值 | `0xff`、`0x5a4d`、`0x401000`、`0x140000000` |
| `i8`、`i16`、`i32`、`i64` | 对应宽度的有符号值 | `-1`、`-200`、`-4096`、`-0x100000000` |
| `usize` | 与宿主地址同宽的无符号值 | `16` |
| `f32` | IEEE-754 32 位浮点数 | `f32(1.5)` |
| `f64` | IEEE-754 64 位浮点数 | `1.5` |
| `bool` | 编译期条件 | `true` |
| `string` | 编译期文本 | `"kernel"` |
| `bytes` | 按字面取值的字节序列 | `b"PE"` |

列表、映射、结构体和类型值在后面的章节介绍。

固定宽度整数用于锁定二进制字段或函数参数；`integer` 用于只关心"是整数"的场合，写出几个字节由调用的输出接口决定。有符号值使用补码，声明时就会检查取值范围：

```asm id=signed-range target=x86-64
const offset: i32 = -1
const too_big: i8 = 200      // 200 放不进 i8
```

```text
bad.xir:2:1: error: the declaration syntax is not valid (InvalidValueDeclaration)
```

数据调用接收无符号值，所以负数要写成它的补码位型：

```asm id=negative-bit-pattern target=x86-64 bytes=ffffffff
dd(0xffffffff)          // -1 的四个字节
```

有符号绑定不会被自动转换：

```asm id=signed-to-data-call target=x86-64
const offset: i32 = -1

dd(offset)
```

```text
bad.xir:3:1: error: lowering failed: InvalidApiInteger
```

带小数部分或指数的十进制字面量类型是 `f64`；`f32(value)` 显式窄化，`f64(value)` 显式扩展。整数和浮点数之间不会隐式转换：

```asm id=float-conversions target=x86-64 bytes=000000000000f83f0000c03f
emit.f64(1.5)          // 带小数的字面量本身就是 f64
emit.f32(f32(1.5))     // f32(...) 显式窄化
```

```asm id=int-float-mismatch target=x86-64
emit.f64(1)            // 1 是整数
```

```text
bad.xir:1:1: error: a call argument does not match what the call expects (InvalidApiArgument)
```

## 字符串与字节序列

`string` 是文本，`bytes` 是按字面取值的字节序列：

```asm id=string-vs-bytes target=x86-64 bytes=2e746578744d5a
const section_name: string = ".text"
const signature: bytes = b"MZ"

db(section_name)       // 2e 74 65 78 74
db(signature)          // 4d 5a
```

文本名称、路径、生成的指令文本，以及要求文本参数的接口都用字符串；需要精确字节序列时用 `bytes`。有些数据接口两者都接受：

```asm id=db-mixed-categories target=x86-64 bytes=41424344
db("AB", b"CD")
```

```text
41 42 43 44
```

## 转义序列

引号字面量使用同一套转义，单引号双引号、带不带 `b` 前缀都一样：

| 转义 | 字节 |
| --- | --- |
| `\n` | 换行，`0x0a` |
| `\r` | 回车，`0x0d` |
| `\t` | 制表符，`0x09` |
| `\0` | NUL，`0x00` |
| `\\` | 一个反斜杠 |
| `\"`（在 `"…"` 中）、`\'`（在 `'…'` 中） | 开启该字面量的那个引号 |
| `\uXXXX` | 该码位的 UTF-8 字节 |

```asm id=escape-decoded target=x86-64 bytes=41c3a9612262610962410942610962
db("\u0041")   // 41：恰好四位十六进制数字对应一个码位
db("\u00e9")   // c3 a9：它的 UTF-8 字节
db("a""b")     // 61 22 62：把开引号写两遍等于一个引号
db("a\tb")     // 61 09 62
db(b"A\tB")    // 41 09 42：`b` 前缀解码同一套转义
db('a\tb')     // 61 09 62：单引号也一样
```

`\uXXXX` 的用途是读回生成的平台文本：Windows API 表用 `"\u0000"` 表示它要的 NUL 字节。除此之外的反斜杠一律原样保留，所以 `\u41` 和 `\ud800` 就是写下的那几个字符：

```asm id=escape-unknown target=x86-64 bytes=5c7534315c7564383030
db("\u41")     // 位数不够
db("\ud800")   // 孤立代理项不是码位
```

要把反斜杠当作数据，就得写成两个：

```asm id=escape-doubled-backslash target=x86-64 bytes=615c7462610962
db("a\\tb")    // 61 5c 74 62：反斜杠是数据
db("a\tb")     // 61 09 62：反斜杠是转义
```

## 块作用域

代码块会创建嵌套作用域：

```asm id=block-scope target=x86-64 bytes=0201
const value = 1

{
    let value = 2   // 在块内遮蔽外层的 `value`
    db(value)       // 02
}

db(value)           // 01：外层绑定重新可见
```

[返回语言指南](../language.md)
