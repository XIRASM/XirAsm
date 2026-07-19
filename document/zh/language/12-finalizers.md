# 第 12 章：收尾处理

很多二进制字段第一次写出来时还不知道最终值：

- 文件头里的大小字段要等 payload 写完才知道；
- PE/ELF/COFF 的 raw pointer、raw size、virtual size 要等区域布局稳定后才能写；
- 校验和要等指令编码、fixup 修补、后期布局都完成后才能算；
- 符号表、字符串表、重定位表可能要等主源码登记完后再生成。

XIRASM 不会反复执行整份源码去“碰运气收敛”。它把后期工作分成两个阶段：

| 阶段 | 能做什么 | 不能做什么 |
| --- | --- | --- |
| `late_layout` | 在最终映像封存前，追加或创建仍会参与布局的真实输出。 | 不能当普通源码块用；不能声明局部变量、标号、函数、循环或写 ISA 指令。 |
| `defer` | 在布局稳定后，读取最终字节、回填已有字段、断言和报错。 | 不能改变布局；不能 `emit`、`reserve`、`align`、切换区域或创建新字节。 |

一句话：**需要新增字节或新增区域，用 `late_layout`；只需要回填已有字节或检查最终结果，用 `defer`。**

## `defer`：回填已经存在的字段

最常见流程是：

1. 先写固定宽度的占位字段；
2. 正常写 payload；
3. 在 `defer` 里把最终值写回占位字段。

```asm
size_field:
emit.u16(0);

payload:
emit.bytes(b"ABC");
payload_end:

defer {
    store.u16(size_field, payload_end - payload);
}
```

最终输出：

```text
03 00 41 42 43
```

`size_field` 的两个字节在普通写出阶段已经存在。`defer` 只是把这两个字节从 `00 00` 改成 `03 00`；它没有插入新字节，也没有移动后面的 payload。

`defer` 可以写在它引用的标号之前：

```asm
defer {
    store.u16(size_field, payload_end - payload);
}

size_field:
emit.u16(0);

payload:
emit.bytes(b"ABC");
payload_end:
```

等 `defer` 执行时，标号已经解析，布局也已经稳定。

## 在 `defer` 中读取和修改最终字节

`load.u8`、`load.u16`、`load.u32`、`load.u64` 读取最终输出中的小端整数。`load.bytes(address, count)` 读取一段字节。

```asm
origin(0x4000);

header:
emit.u32(0);
emit.u32(0);

body:
emit.bytes(b"ABCD");
tail:
emit.bytes(b"????");
image_end:

defer {
    store.u32(header, image_end - body);
    store.u32(header + 4, body - region_base());
    store.bytes(tail, b"OK!!");

    assert(load.u32(header) == 8);
    assert(load.u32(header + 4) == 8);
    assert(load.bytes(tail, 4) == b"OK!!");
}
```

最终输出：

```text
08 00 00 00 08 00 00 00 41 42 43 44 4f 4b 21 21
```

所有 `load.*` 和 `store.*` 都会检查范围。`defer` 只能访问最终文件里真实存在的字节。第 11 章说过，尾部 `reserve` 可能只增加逻辑大小，不进入 raw 文件；这种被裁掉的尾部预留不能当成可写占位字段。

`store.bytes` 接受字符串或 `bytes` 值。整数写入会检查宽度，值放不进目标宽度时会报错。

## 计算校验和

`defer` 内可以声明 `const`、`let`，可以给局部 `let` 赋值，也可以用有界 `while`。

```asm
origin(0x5000);

checksum:
emit.u16(0);

payload:
emit.bytes(b"ABCD");
payload_end:

defer {
    let cursor = payload
    let sum = 0

    while cursor < payload_end {
        sum = sum + load.u8(cursor)
        cursor = cursor + 1
    }

    store.u16(checksum, sum);
    assert(load.u16(checksum) == 266);
}
```

`266` 是 `0x010a`，最终输出：

```text
0a 01 41 42 43 44
```

`while` 使用普通 Meta 循环的编译期迭代限制。`for` 目前不能放进 `defer`；需要扫描字节时，用边界清楚的 `while`。

## 查询最终区域信息

第 11 章的区域最终信息只能在 `defer` 中查询，因为它们依赖最终布局：

```asm
region.begin("payload", 0x5000, 0);

file_size_field:
emit.u32(0);
logical_size_field:
emit.u32(0);

body:
emit.u8(0xaa);
reserve(3);

defer {
    store.u32(file_size_field, region_file_size(body));
    store.u32(logical_size_field, region_logical_size(body));

    assert(region_file_offset(body) == 0);
    assert(region_file_size(body) == 9);
    assert(region_logical_size(body) == 12);
}
```

输出：

```text
09 00 00 00 0c 00 00 00 aa
```

这里文件大小是 9：两个 `u32` 字段占 8 字节，`body` 占 1 字节。尾部 `reserve(3)` 不写入 raw 文件，所以不计入 `region_file_size`。逻辑大小是 12，因为尾部 reserve 仍然占逻辑地址范围。

三个查询分别是：

- `region_file_offset(address)`：包含该地址的区域最终从哪个 FOA 开始；
- `region_file_size(address)`：该区域最终写入 raw 文件的字节数；
- `region_logical_size(address)`：该区域最终占用的逻辑地址大小，包含尾部 reserve。

它们不是写出阶段的“当前 FOA”查询。需要当前 FOA 时用 `file_offset()` / `file_cursor_real()`；需要最终区域大小时，在 `defer` 里用 `region_file_*` / `region_logical_size`。

## 用函数登记回填逻辑

过程函数可以登记 `defer` 块，并捕获调用时传入的参数：

```asm
fn patch_u16(address: u64, value: u64) {
    defer {
        store.u16(address, value);
    }
}

field:
emit.u16(0);

patch_u16(field, 0x1234);
```

最终输出：

```text
34 12
```

注意执行时机：`patch_u16(...)` 在普通源码阶段调用；调用时的 `address` 和 `value` 被保存到登记的 `defer` 块里。真正写字节发生在最终布局稳定之后。

这种写法适合做类型明确的小型回填工具，比如 `patch_u32`、`patch_size_field`、`patch_checksum_field`。

## `defer` 的允许范围

`defer` 适合最终检查和回填。它可以使用：

- `const`、`let` 和局部赋值；
- `if` / `else`；
- `while`、`break`、`continue`；
- `load.*`、`store.u8/u16/u32/u64`、`store.bytes`；
- `assert`、`print`、`warn`、`err`；
- 纯表达式和值函数；
- 标签、最终区域信息、已稳定的输出字节。

它不能做任何会改变布局的事。例如：

```text
defer {
    emit.u8(0x22);
}
```

会被拒绝。下列操作也不允许放在 `defer` 中：

- 写 ISA 指令；
- 定义标号；
- `emit.*`、`db/dw/dd/...`；
- `reserve`、`align`、`pad`、`pad_to`；
- `origin`、`region.begin`、`output.section`、`output.org`、`virtual.begin`；
- 嵌套 `defer` 或 `late_layout`；
- 声明函数、结构体或加载源文件；
- 读外部文件。

需要空间就提前写占位或在 `late_layout` 里创建；`defer` 只能修改已经存在的字节。

## 多个 `defer` 的执行顺序

`defer` 按登记顺序执行：

```asm
emit.u8(0);

defer {
    store.u8(0, 1);
}

defer {
    store.u8(0, load.u8(0) + 1);
}
```

第二个块能看到第一个块的修改，所以最终输出是：

```text
02
```

如果多个 `defer` 修改同一地址，后执行的块会看到前面的结果。不要把同一个字段分散到多个互相依赖的 `defer`，除非顺序就是你想要的格式规则。

`defer` 运行在这些步骤之后：

1. 普通源码处理；
2. `late_layout`；
3. 指令编码和布局松弛；
4. fixup 解析；
5. 最终文件字节生成；
6. fixup 修补。

因此 `defer` 看到的是即将写出的最终映像：指令已经编码，引用已经解析，后期布局创建的字节也已经进入最终布局。

## `late_layout`：封存前新增真实布局

`late_layout` 用于“主源码已经登记完，但最终布局还没封存”时创建真实输出。

最简单的形式是追加字节：

```asm
emit.u8(0x10);

late_layout {
    emit.u8(0x20);
}

late_layout {
    emit.u8(0x30);
}
```

`late_layout` 块按登记顺序执行一次，默认从默认输出区域的尾部继续。输出是：

```text
10 20 30
```

这说明默认行为是“接在当前默认输出尾部”。但 `late_layout` **不是只能追加到整个文件末尾**。它允许调用输出区域 API，所以你可以在块中显式打开一个真实区域，把晚生成的数据放到你指定的 FOA。

例如，先在虚拟区域里生成表，再在后期布局阶段把表放到指定 raw 文件偏移：

```asm
table_foa_field:
emit.u32(0);
emit.bytes(b"HDR");

const table_origin: u64 = 0x8000
const table_foa: u64 = 0x10

virtual.begin(0);
table_tmp:
emit.bytes(b"TAB");
table_tmp_end:
virtual.end();

late_layout {
    region.begin("late-table", table_origin, table_foa);
    emit.bytes(load.bytes(table_tmp, table_tmp_end - table_tmp));
}

defer {
    store.u32(table_foa_field, table_foa);
}
```

这里 `late_layout` 没有“往最终文件里插入字节”。它是在最终映像生成前创建了一个真实区域：逻辑地址从 `0x8000` 开始，raw 文件偏移从 `0x10` 开始。最终文件怎么补洞、是否重叠、头字段是否一致，都由调用者的区域布局负责。

如果你已经用 `region.begin` / `output.section` / `output.org` 构造了类似 PE 的多段布局，那么 `late_layout` 中的晚生成表也可以放进某个明确的自定义区域；前提是你显式切到那个区域或给出正确 FOA。只写 `emit.*` 时才是沿默认输出尾部继续。

标准 PE/COFF/ELF 优先用第 14 章的 `format.inc` 接口。直接写 `late_layout + region.begin` 更适合自定义格式，或者实现格式库内部的符号表、字符串表、重定位表等晚生成内容。

## `late_layout` 会影响尾部 reserve

因为 `late_layout` 发生在最终布局之前，它新增的真实字节会参与 raw 文件布局。追加在尾部 reserve 后面时，前面的 reserve 会变成文件中间的零填充：

```asm
emit.u8(0xaa);
reserve(3);

late_layout {
    emit.u8(0xbb);
}
```

最终输出：

```text
aa 00 00 00 bb
```

如果这不是你想要的行为，不要在同一个区域尾部 reserve 后直接追加真实字节。先用 `output.section` 裁掉尾部 reserve，或用 `region.begin` 切到明确的目标区域。

## `late_layout` 的限制

`late_layout` 比普通源码窄得多。它只接受 API 调用和 `if` 分支；没有普通局部作用域。

允许的方向包括：

- `emit.*`、`emit.bytes`、`emit.struct`、`db/dw/dd/...`；
- `reserve`、`pad`、`pad_to`、`align`；
- `origin`、`region.begin`、`region.file_align`；
- `output.section`、`output.org`；
- `virtual.begin`、`virtual.end`；
- `store.u8/u16/u32/u64`、`store.bytes`；
- `assert`、`print`、`warn`、`err`；
- `if` / `else`。

不允许：

- `let` / `const` 声明；
- 赋值；
- `while` / `for`；
- 标号；
- ISA 指令文本；
- 函数、结构体、嵌套 `late_layout` 或 `defer`；
- 读外部文件或加载源模块。

需要计算的值、字节数组、表大小、目标 FOA，应在普通源码阶段先算好，再作为 API 参数用于 `late_layout`。需要读文件时，也应在普通阶段读取成 `bytes`，不要在 `late_layout` 或 `defer` 里读。

`late_layout` 只执行一次。它不是依赖反复执行源码来收敛不稳定值的多遍模型。

## 选择阶段

用普通源码：

- 字节可以按正常顺序写出；
- 标号、局部变量、函数、循环、文件读取都需要正常语言能力。

用 `late_layout`：

- 必须等主源码登记完后才知道要写哪些真实字节；
- 晚生成表、字符串池、重定位记录需要进入最终文件；
- 需要显式放到某个 FOA 或沿默认输出尾部继续；
- 这些字节必须影响最终 raw size、logical size、偏移和回填。

用 `defer`：

- 固定宽度占位字段需要最终值；
- 校验和需要完整最终字节；
- 需要最终 `region_file_offset` / `region_file_size` / `region_logical_size`；
- 只修补已有字节，不创建空间。

常见安全规则：

- 不要用 `defer` 创建缺失空间；
- 不要在 `late_layout` 里写需要普通局部变量和循环的逻辑；
- 不要把尾部 reserve 是否进入文件交给猜测，明确选择 `output.section` 或 `output.org`；
- 构造标准 PE/COFF/ELF 时优先使用 `format.inc`，不要手写重复的布局关系。

下一章进入第三部分，介绍 flat 和自定义二进制文件：如何把标签、结构体、区域、后期布局和收尾回填组合成完整文件格式。

## 第三部分：构建程序

[返回目录](../language.md)
