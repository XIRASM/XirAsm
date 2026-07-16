# 第 11 章：输出区域与虚拟数据

汇编里两个基本问题：值在什么地址？字节写在文件什么位置？

flat binary 里两者同步，从零一起涨。结构化二进制里两者分开：代码段加载到高地址，文件偏移可能就在文件头后面；reserve 占地址空间但不写文件；临时拼的数据不进入最终文件。

本章说明输出区域、逻辑地址和文件位置的关系。这些概念在构建自定义二进制文件或使用格式接口时都很有用。

XIRASM 用输出区域分开这两套值。

## 地址和文件位置

每个普通区域有四条属性：

- **origin**：标签地址的基准
- **file offset**：字节在文件里的位置
- **logical size**：含预留的逻辑地址范围
- **file size**：实际落盘的字节数

四项互相独立。改 origin 不插入填充，改 file offset 不改标签值。

常用查询：

| 查询                        | 含义                           |
| --------------------------- | ------------------------------ |
| `region_base()`           | 当前区域的 origin              |
| `here()`                  | 当前逻辑地址                   |
| `file_offset()`           | 当前文件位置                   |
| `file_cursor_real()`      | 已写入的文件末端               |
| `file_cursor_potential()` | 假设所有预留均落盘时的文件末端 |
| `tail_reserve_size()`     | 当前区域尾部未落盘的预留字节数 |

光标查询用于构造自定义布局或格式辅助函数。普通代码用标签和 `here()` 就够。

## origin 设地址基准

`origin(address)` 设定当前区域的地址起点：

```asm
// 把当前输出区域的逻辑起点设为 0x4000。
origin(0x4000);

start:
// 在起始地址处写出一个字节。
emit.u8(0xaa);

// 检查区域起点、标号地址、当前位置和文件位置。
assert(region_base() == 0x4000);
assert(label_addr("start") == 0x4000);
assert(here() == 0x4001);
assert(file_offset() == 1);
```

输出一字节：

```text
aa
```

origin 改标签地址，不改文件位置。flat 区域里先设 origin 再写出。再次调 `origin` 更新当前区域基准，不创建新区域。

## region.begin 指定两个值

`region.begin(name, origin, file_offset)` 同时设逻辑地址和文件偏移：

```asm
// 头部的逻辑地址从 0x1000 开始，文件位置从 0 开始。
region.begin("header", 0x1000, 0);

header:
emit.bytes(b"HD");

// 数据使用独立的逻辑地址，并从文件偏移 0x10 开始。
region.begin("payload", 0x2000, 0x10);

payload:
emit.bytes(b"DATA");

// 两个标号分别使用各自输出区域的起始地址。
assert(label_addr("header") == 0x1000);
assert(label_addr("payload") == 0x2000);
```

header 占文件偏移 0 和 1，payload 从 0x10 开始。中间未写的部分在 flat 输出里补零：

```text
48 44 00 00 00 00 00 00 00 00 00 00 00 00 00 00
44 41 54 41
```

开新区域即切换当前输出区。区域之间没有嵌套关系，不需要 end 语句。

区域名描述源码的布局意图，不自动生成目标文件格式的 section 记录——后者由格式库管。

两个值都已知时用 `region.begin`。顺序构造场景用 `output.section` 和 `output.org` 更稳妥，它们自动推导后续文件偏移。

## 实际位置 vs 预留位置

写已初始化字节时，两个光标同步推进：

```asm
// 写出一个实际存在于文件中的字节。
emit.u8(0xaa);

// 实际位置和潜在位置都前进到 1，尾部没有预留空间。
assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 1);
assert(tail_reserve_size() == 0);
```

`reserve` 只推潜在光标和逻辑地址，不落盘：

```asm
// 先写出一个字节，再预留三个尚未实际写入的字节。
emit.u8(0xaa);
reserve(3);

// 逻辑位置已经前进四字节，实际文件仍只有一个字节。
assert(here() == 4);
assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 4);
assert(tail_reserve_size() == 3);
```

预留后面出现初始化数据时，预留范围变成文件中间的间隙：

```asm
// 后续字节使前面的预留范围成为文件中的实际间隔。
emit.u8(0xaa);
reserve(3);
emit.u8(0xbb);

// 中间间隔已经实际形成，两个文件位置重新一致。
assert(file_cursor_real() == 5);
assert(file_cursor_potential() == 5);
assert(tail_reserve_size() == 0);
```

文件内容：

```text
aa 00 00 00 bb
```

`reserve` 延迟落盘的特性让它同时表达两种形态：文件中间的零填充间隙，和不占文件空间的尾部预留。

## output.section 裁掉尾部

`output.section(name, origin)` 从当前**实际**光标处开新区域。

```asm
// 第一个区域包含一个实际字节和三个尾部预留字节。
emit.u8(0x41);
reserve(3);

// 新区域紧接最后一个实际字节，尾部预留空间不进入文件。
output.section("next", 0x2000);
emit.u8(0x42);
```

尾部预留增大第一区域的逻辑大小，但新区域从最后一个已写入字节之后开始。输出：

```text
41 42
```

适用于运行时需要地址范围但文件末尾不占空间的场景。

`output.section` 只丢弃未落盘的尾部预留，文件中间的间隙不受影响。

## output.org 保留间隙

`output.org(name, origin)` 从当前**潜在**光标处开新区域。

```asm
// 第一个区域的潜在长度为四字节。
emit.u8(0x41);
reserve(3);

// 新区域从潜在位置开始，因此保留前面的三字节间隔。
output.org("next", 0x2000);
emit.u8(0x42);
```

预留之后写入数据，预留范围保留在文件中：

```text
41 00 00 00 42
```

区别：

| 操作               | 下一个文件偏移起点     |
| ------------------ | ---------------------- |
| `output.section` | 实际光标，裁尾部预留   |
| `output.org`     | 潜在光标，保留预留范围 |

两个操作各自独立选择新的逻辑 origin，与文件位置无关。

## region.file_align 对齐文件大小

`region.file_align(alignment)` 对齐当前区域最终的物理文件大小。

```asm
// 第一个区域从逻辑地址 0x1000、文件偏移 0 开始。
region.begin("first", 0x1000, 0);

// 三个实际字节之后还有十三个尾部预留字节。
emit.bytes(b"ABC");
reserve(13);

assert(here() == 0x1010);
assert(file_cursor_real() == 3);
assert(file_cursor_potential() == 16);

// 去除尾部预留空间，再把实际文件大小向上对齐到八字节。
region.file_align(8);

// 第二个区域从已经对齐的文件偏移 8 开始。
region.begin("second", 0x2000, 8);
emit.u8(0x5a);
```

裁掉尾部预留后，三个物理字节按 8 字节边界对齐。第二区域起始文件偏移 8：

```text
41 42 43 00 00 00 00 00 5a
```

文件对齐不改逻辑大小——第一区域逻辑大小仍为 16。

对齐值必须是 2 的正整数次幂。调 `region.file_align` 后当前区域的物理输出已关闭，写字节前要先开新区域。

与 `align` 的区别：`align` 推进逻辑位置并在间隙落盘时填填充字节；`region.file_align` 只确定文件大小的对齐边界，不改逻辑地址。

## 虚拟区域：临时工作区

虚拟区域是汇编期间的独立工作区。字节、标签和指令可检查可修改，但不自动汇入最终输出。

`virtual.begin(origin)` 在指定逻辑地址创建虚拟区域：

```asm
// 在逻辑地址 0x3000 创建一个临时虚拟区域。
virtual.begin(0x3000);

table:
emit.u32(0x11223344);
// 读取原值、逐位变换后，再写回同一位置。
store.u32(table, load.u32(table) ^ 0x01010101);
const encoded: bytes = load.bytes(table, 4)

virtual.end();

// 只有显式复制出的字节才会进入主输出。
emit.bytes(encoded);
```

临时区域初始内容：

```text
44 33 22 11
```

变换后复制到主输出：

```text
45 32 23 10
```

虚拟区域本身不贡献文件字节。

虚拟区域里可以正常写出、预留、对齐、定义标签、写 ISA 指令。`load.*` 和 `store.*` 对其字节同样生效。每个 `virtual.begin` 对应一个 `virtual.end`。

## 省略 origin：用当前地址

省略 origin 参数时，虚拟区域从外围区域的当前逻辑地址开始：

```asm
// 主输出从逻辑地址 0x4000 开始，并先写出一个字节。
origin(0x4000);
emit.u8(0xaa);

// 省略参数，使虚拟区域沿用当前逻辑地址 0x4001。
virtual.begin();

scratch:
emit.u16(0x1234);
const copied: bytes = load.bytes(scratch, 2)

virtual.end();

// 显式把临时生成的两个字节追加到主输出。
emit.bytes(copied);
```

`scratch` 逻辑地址 0x4001，但其虚拟字节不替换也不推进外围区域。`virtual.end` 后主输出从暂停处继续。最终文件：

```text
aa 34 12
```

适用于编码需临时组装、且标签地址需与目标位置共用同一基准的场景。

## 区域最终数据 defer 才可查

写出阶段只有实时光标可用。区域最终的文件偏移和大小等布局稳定后才确定。以下查询只在收尾处理阶段可用：

| 查询                             | 对包含指定地址的区域返回 |
| -------------------------------- | ------------------------ |
| `region_file_offset(address)`  | 区域在文件中的基偏移     |
| `region_file_size(address)`    | 最终物理大小             |
| `region_logical_size(address)` | 最终逻辑大小             |

收尾处理中可用这些值填充文件头，或校验自定义格式的大小与最终布局是否吻合。下一章详述收尾处理。

## 怎么选

只用 origin：

- 单个 flat 流需非零地址基准
- 文件和逻辑位置同步推进

`output.section`：

- 下一段从已写字节后开始
- 尾部预留扩内存但不占文件

`output.org`：

- 下一段从潜在位置继续
- 预留范围须保留在文件中

`region.begin`：

- 逻辑 origin 和文件偏移都明确
- 自定义二进制布局或格式辅助函数

虚拟区域：

- 临时组装、测量、读取或变换数据
- 临时字节不得自动进入主输出

总结：

- 标签和 `here()` 表逻辑地址
- 实际光标只反映已落盘的字节
- 潜在光标包含当前尾部预留
- 区域最终数据只在收尾处理阶段可读

下一章介绍收尾处理：读取已稳定的布局信息、修补字节、计算校验和、验证映像，不改变布局。

[返回目录](../language.md)
