# 第 9 章：数据与二进制布局

指令只是输出字节的一种来源。文件头、查找表、消息、常量、预留空间和应用程序专用记录，都需要明确的二进制布局。

XIRASM 提供两个互补的层次：

- 数据写出接口负责写出精确的整数、字符串和字节值；
- 二进制复合类型用于描述可复用的结构体和联合体。

对于较短的布局和孤立字段，可以直接写出数据。当多个字段共同组成一个具名记录，并且需要把该记录作为整体创建、检查或写出时，应使用复合类型。

## 输出内容是有序字节序列

数据调用会在当前输出位置追加字节：

```asm
// 按 1、2、4、8 字节的宽度依次写出整数。
emit.u8(0x11);
emit.u16(0x2233);
emit.u32(0x44556677);
emit.u64(0x0102030405060708);
```

这些整数接口按小端顺序写出值。生成的字节为：

```text
11
33 22
77 66 55 44
08 07 06 05 04 03 02 01
```

每个接口都会检查传入值能否放入指定宽度。如果值超出范围，应改用更宽的接口，而不是让它被静默截断。

对应的简写如下：

| 简写 | 宽度 | 等效用途 |
| --- | --- | --- |
| `db` | 1 字节 | 字节值、字符串和 `bytes` 值 |
| `dw` | 2 字节 | 小端整数 |
| `dd` | 4 字节 | 小端整数 |
| `dp` | 6 字节 | 小端整数 |
| `dq` | 8 字节 | 小端整数 |
| `dt` | 10 字节 | 从 `u64` 零扩展的小端整数 |
| `ddq` | 16 字节 | 从 `u64` 零扩展的小端整数 |
| `dqq` | 32 字节 | 从 `u64` 零扩展的小端整数 |
| `ddqq` | 64 字节 | 从 `u64` 零扩展的小端整数 |

例如：

```asm
// 使用简写按固定宽度写出同一组小端整数。
db(0x41);
dw(0x1122);
dd(0x33445566);
dq(0x0102030405060708);
```

这些简写都可以接受多个实参。除 `db` 外，每个实参都必须是整数；`db` 还可以接受字符串和字节序列。1、2、4、6、8 字节宽度会严格检查范围。当前 Meta 整数为 `u64`，所以 10、16、32、64 字节宽度会进行零扩展。需要精确的宽位模式时应使用 `emit.bytes`。`dt` 只表示 10 字节原始数据，不会引入 `f80` 或 x87 浮点类型。

## 浮点值

浮点写出与整数数据简写保持独立：

```asm
const scale: f64 = 1.5
const compact: f32 = f32(scale)

emit.f32(compact);
emit.f64(scale * 2.0);
```

`emit.f32` 和 `emit.f64` 分别写出小端 IEEE-754 binary32 和 binary64 编码，实参必须已经具有完全匹配的类型。浮点运算和比较也要求两侧类型一致。字面量、转换和运算结果必须保持有限；溢出、NaN 和 Infinity 会被拒绝，有限下溢与有符号零会被保留。

## 字符串与字节序列

一次 `db` 调用可以同时组合字节值、字符串和 `bytes` 值：

```asm
// suffix 保存需要原样接在文本之后的两个字节。
const suffix: bytes = b"CD"

// 依次写出字节 A、字符串 B、字节序列 CD 和显式终止零。
db(0x41, "B", suffix, 0);
```

这会写出：

```text
41 42 43 44 00
```

字符串和字节序列都会被原样复制。XIRASM 不会自动添加结尾的零字节；如果文件格式、应用程序二进制接口或运行时接口要求终止零，必须显式写出。

`emit.bytes(value)` 用于写出一个字符串或 `bytes` 值：

```asm
// 从十六进制文本构造精确的四字节签名。
const signature: bytes = bytes.from_hex("7f454c46")

// 先写出二进制签名，再直接写出四个文本字节。
emit.bytes(signature);
emit.bytes("DATA");
```

当一个值表示精确的二进制内容时，应使用 `bytes`。当一个值表示源代码层面的文本，只是恰好需要直接写出时，应使用字符串。

## 预留空间

`reserve(count)` 会让输出位置前进指定的字节数：

```asm
// 在两个已初始化字节之间预留两个字节。
db(0xeb);
reserve(2);
db(0xfe);
```

在普通裸二进制文件中，这会写出：

```text
eb 00 00 fe
```

预留空间简写会把数量乘以对应的元素宽度：

| 简写 | 预留字节数 |
| --- | --- |
| `rb(count)` | `count` |
| `rw(count)` | `count * 2` |
| `rd(count)` | `count * 4` |
| `rp(count)` | `count * 6` |
| `rq(count)` | `count * 8` |
| `rt(count)` | `count * 10` |
| `rdq(count)` | `count * 16` |
| `rqq(count)` | `count * 32` |
| `rdqq(count)` | `count * 64` |

```asm
// 预留两个字节，写出 aa，再预留两个字节并写出 bb。
rb(2);
db(0xaa);
rw(1);
db(0xbb);
```

这会依次写出两个零字节、`aa`、另外两个零字节和 `bb`。

预留操作表达的是未使用的空间，而不是具有实际意义的已初始化内容。如果后面还有已初始化的输出内容，那么预留范围会在裸二进制文件中成为真实的零填充间隙。如果连续的预留空间位于末尾，则可能只增加逻辑大小，而不占用文件字节。第 11 章会通过输出区域的实际文件游标和潜在文件游标解释这一区别。

## 填充与对齐

`pad(count, fill)` 会写出指定数量的重复字节：

```asm
// 在 01 与 02 之间写出三个 aa 填充字节。
db(1);
pad(3, 0xaa);
db(2);
```

结果为：

```text
01 aa aa aa 02
```

填充值实参可以省略，默认值为零：

```asm
// 使用默认填充值写出四个零字节。
pad(4);
```

`pad_to(position, fill)` 会持续写出填充字节，直到当前输出字节位置达到指定位置：

```asm
// 当前位置为 2；用 90 填充到位置 6，再写出 33。
db(0x11, 0x22);
pad_to(6, 0x90);
db(0x33);
```

这会写出：

```text
11 22 90 90 90 90 33
```

指定位置不能位于当前输出位置之前。

`align(boundary, fill)` 会让输出位置前进到边界的下一个整数倍：

```asm
// 三个初始字节之后，用 cc 补齐到 8 字节边界。
db(0x11, 0x22, 0x33);
align(8, 0xcc);
db(0x44);
```

这会在 `44` 之前写出五个 `cc` 字节。填充值实参默认也是零。

对齐边界必须是非零的二次幂。1、2、4、16 和 4096 等值有效，3 或 24 等值会被拒绝。

应根据意图选择操作：

| 需求 | 使用 |
| --- | --- |
| 已知大小的未初始化空间 | `reserve` 或 `rb`/`rw`/`rd`/`rp`/`rq`/`rt`/`rdq`/`rqq`/`rdqq` |
| 精确数量的填充字节 | `pad` |
| 到达已知输出位置 | `pad_to` |
| 到达下一个对齐位置 | `align` |

## 声明二进制结构体

结构体为一组顺序排列的字段指定名称和类型：

```asm
// 自然布局会按字段类型的对齐要求安排偏移。
struct NaturalHeader {
    tag: u8
    size: u32
}
```

这是一个自然对齐的结构体。`tag` 从偏移 0 开始。`u32` 字段要求按四字节对齐，因此 `size` 从偏移 4 开始。整个结构体占八个字节：

```text
偏移 0：tag
偏移 1：填充
偏移 2：填充
偏移 3：填充
偏移 4：size
偏移 5：size
偏移 6：size
偏移 7：size
```

自然布局会对齐每个字段，并把最终大小向上取整到结构体的对齐要求。它适合布局应遵循各字段对齐要求的内存记录。

如果需要精确的文件布局，应声明紧凑结构体：

```asm
// packed 禁止在字段之间和结构体末尾自动插入填充。
packed struct FileHeader {
    tag: u8
    size: u32
}
```

`FileHeader` 占五个字节。`size` 从偏移 1 开始，紧接在 `tag` 之后，末尾也没有填充。

文件头、协议记录、指令元数据和其他由外部规范规定的字节布局，通常应使用紧凑布局。原生内存记录通常应使用自然布局。

## 字段默认值与结构体字面量

字段可以提供编译期默认值：

```asm
// magic 和 flags 提供默认值，size 由每个实例显式指定。
packed struct Header {
    magic: u16 = 0x5a4d
    flags: u16 = 1
    size: u32
}

// 字面量只覆盖 size，其余字段沿用声明中的默认值。
const header: Header = Header {
    size: 0x40
}

// 通过普通字段访问读取需要写出的成员。
emit.u16(header.magic);
emit.u32(header.size);
```

这个字面量提供了 `size`，并对 `magic` 和 `flags` 使用默认值。字面量中的字段按名称匹配，而不是按源码中的排列顺序匹配。

每个省略的字段都必须具有默认值。未知字段、重复字段和值类型不正确的字段都会导致源代码错误。

字段可以使用普通的字段访问语法读取，如示例中的两个写出调用所示。

复合值存在于汇编期间。仅仅声明复合值并不会自动把它写入输出内容。

## 测量布局

`sizeof(Type)` 返回二进制类型的完整大小：

```asm
// 自然布局需要为 u32 字段和结构体末尾保留对齐空间。
struct NaturalHeader {
    tag: u8
    size: u32
}

// 紧凑布局保持字段连续排列。
packed struct PackedHeader {
    tag: u8
    size: u32
}

// 同时验证两种布局的总大小和关键字段偏移。
assert(sizeof(NaturalHeader) == 8);
assert(sizeof(PackedHeader) == 5);
assert(offset_of(NaturalHeader, tag) == 0);
assert(offset_of(NaturalHeader, size) == 4);
assert(offset_of(PackedHeader, size) == 1);
```

`offset_of(Type, field)` 返回字段偏移。这两个操作都是编译期表达式，可以用于指令、写出字段、断言和其他布局计算：

```asm
// 选择 64 位 x86 指令编码。
x86.use64();

// 两个 64 位寄存器槽位组成连续的保存区。
packed struct SaveArea {
    rax: u64
    rcx: u64
}

// 根据结构体大小调整栈指针，避免硬编码保存区字节数。
sub rsp, sizeof(SaveArea)
```

使用符号化的布局计算，可以避免新增字段或更改类型后，源代码其他位置仍残留过期的硬编码大小。

## 打包并写出结构体值

`pack(value)` 会把复合值转换为 `bytes` 值：

```asm
// 两个小端 u16 字段共同组成四个连续字节。
packed struct Header {
    magic: u16 = 0x4241
    tail: u16
}

const header: Header = Header {
    tail: 0x4443
}

// 先打包以便比较，再把同一字节序列写入输出。
const encoded: bytes = pack(header)
assert(encoded == b"ABCD");
emit.bytes(encoded);
```

`emit.struct(value)` 会直接完成打包和写出：

```asm
// 自然布局会在 tag 与 size 之间加入三个零填充字节。
struct NaturalHeader {
    tag: u8 = 0x41
    size: u32 = 0x11223344
}

// 空字面量使用所有字段默认值，并立即写出完整结构体布局。
const header: NaturalHeader = NaturalHeader { }
emit.struct(header);
```

这会写出八个字节，其中自然布局产生的三个填充字节都是零：

```text
41 00 00 00 44 33 22 11
```

如果还需要比较、转换、把字节序列保存在集合中，或者把它传给另一个函数，应使用 `pack`。如果只需要立即写出该值，应使用 `emit.struct`。

## 联合体与当前字段

联合体会让多个不同类型的字段重叠在偏移 0：

```asm
// Point 的两个坐标以紧凑形式连续存放。
packed struct Point {
    x: u16
    y: u16
}

// raw 与 point 共享同一段四字节存储。
union ValueBits {
    raw: u32
    point: Point
}

// 此字面量选择 point 作为联合体的当前字段。
const coordinates: ValueBits = ValueBits {
    point: Point {
        x: 0x1122,
        y: 0x3344
    }
}
```

联合体的每个字段都从偏移 0 开始。自然布局的联合体以最大字段大小为基础，再按最大的字段对齐要求向上取整。`packed` 联合体则直接使用最大字段的精确大小。

`coordinates` 字面量只选择一个当前字段。联合体字面量既不能省略所有字段，也不能同时初始化多个字段。

联合体还可以嵌套在结构体中：

```asm
// Point 描述联合体的一种四字节解释方式。
packed struct Point {
    x: u16
    y: u16
}

union ValueBits {
    raw: u32
    point: Point
}

// 紧凑记录把种类字节与联合体内容连续排列。
packed struct Record {
    kind: u8
    value: ValueBits
}

// 此实例选择 raw 作为嵌套联合体的当前字段。
const record: Record = Record {
    kind: 1,
    value: ValueBits {
        raw: 0xaabbccdd
    }
}

// 嵌套字段路径会累计外层和内层字段的偏移。
assert(offset_of(Record, value) == 1);
assert(offset_of(Record, value.point.y) == 3);
emit.struct(record);
```

如示例中的两个断言所示，`offset_of` 支持嵌套字段路径。

第二个结果把 `value` 在 `Record` 中的偏移，与 `y` 在 `Point` 中的偏移相加。

## 选择布局方式

以下情况适合直接写出整数和字节：

- 布局只有少数字段；
- 字段只写出一次，之后不再需要名称；
- 源代码紧密对应某个外部表格，显式调用比类型声明更清晰。

以下情况适合使用紧凑结构体和联合体：

- 精确的二进制记录会被重复使用；
- 字段名称可以提高可读性；
- 其他计算应由 `sizeof` 和 `offset_of` 驱动；
- 值需要默认值、嵌套、比较或转换为 `bytes`。

以下情况适合使用自然布局结构体：

- 记录表示对齐的内存，而不是序列化后的文件布局；
- 填充是有意保留的，并且应遵循字段对齐要求。

对于由外部规范定义的布局，始终应使用 `sizeof` 和 `offset_of` 断言进行验证。这些断言会把格式假设变成可执行检查，并让后续修改更加稳妥。

下一章将介绍模块与文件：通过 `include` 和 `import` 复用源代码，以及在汇编期间读取外部文本、字节、JSON 和 TOML。

[返回语言指南](../language.md)
