# 第 12 章：收尾处理

很多二进制字段第一次写出来时还不知道最终值：

- 文件头里的大小字段要等 payload 写完才知道；
- PE/ELF/COFF 的 raw pointer、raw size、virtual size 要等区域布局稳定后才能写；
- 校验和要等指令编码、fixup 修补、后期布局都完成后才能计算；
- 符号表、字符串表、重定位表可能要等主源码登记完再生成。

同第十一章一样，不想了解可执行格式可不用看，因为如果你用了可执行格式，那么这些乱用会让二进制布局混乱。也是普通用户不是必须学习的章节。

XIRASM 不会反复执行整份源码去"碰运气收敛"。后期工作分两个阶段：

| 阶段            | 能做什么                                               | 不能做什么                                                                 |
| --------------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| `late_layout` | 在最终映像封存前，追加或创建仍会参与布局的真实输出。   | 不能当普通源码块用；不能声明局部变量、标号、函数、循环或写 ISA 指令。      |
| `defer`       | 在布局稳定后，读取最终字节、回填已有字段、断言和报错。 | 不能改变布局；不能`emit`、`reserve`、`align`、切换区域或创建新字节。 |

要新增字节或新增区域，用 `late_layout`；只回填已有字节或检查最终结果，用 `defer`。

## `defer` 回填已经存在的字段

最常见的流程是：先写固定宽度的占位字段，再正常写 payload，最后在 `defer` 里把最终值写回占位字段。

```asm id=12-u16 bytes=0300414243
size_field:
emit.u16(0)                   // 占位两字节，值还不知道

payload:
emit.bytes(b"ABC")
payload_end:

defer {
    // payload 的真实长度在这里才算得出来。
    store.u16(size_field, payload_end - payload)
}
```

最终输出：

```text
03 00 41 42 43
```

`size_field` 那两个字节在普通写出阶段就已经存在。`defer` 只是把它们从 `00 00` 改成 `03 00`；它没有插入新字节，也没有挪动后面的 payload。

`defer` 可以写在它引用的标号之前：

```asm id=12-u16-2
defer {
    // defer 写在标号之前也可以：执行时这些标号已经解析完了。
    store.u16(size_field, payload_end - payload)
}

size_field:
emit.u16(0)

payload:
emit.bytes(b"ABC")
payload_end:
```

等 `defer` 执行时，这些标号已经解析完，布局也已经稳定。

## 读取和改写最终字节

`load.u8`、`load.u16`、`load.u32`、`load.u64` 读最终输出里的小端整数，`load.bytes(address, count)` 读一段字节。

`load.*` 和 `store.*` 只能碰最终映像里真实存在的字节。尾部 `reserve` 不在文件里，终结器读写那一段会失败，诊断会写明地址、宽度和文件长度。

```asm id=12-origin bytes=0800000008000000414243444f4b2121
origin(0x4000)

header:
emit.u32(0)                   // 后面回填 body 的长度
emit.u32(0)                   // 后面回填 body 的逻辑地址

body:
emit.bytes(b"ABCD")
tail:
emit.bytes(b"????")           // 占位，稍后改写
image_end:

defer {
    store.u32(header, image_end - body)          // body 到映像末尾的长度
    store.u32(header + 4, body - region_base())  // body 的逻辑地址
    store.bytes(tail, b"OK!!")                   // 覆盖占位

    assert(load.u32(header) == 8)
    assert(load.u32(header + 4) == 8)
    assert(load.bytes(tail, 4) == b"OK!!")
}
```

最终输出：

```text
08 00 00 00 08 00 00 00 41 42 43 44 4f 4b 21 21
```

所有 `load.*` 和 `store.*` 都检查范围。`defer` 只能访问最终文件里真实存在的字节。

第 11 章说过，尾部 `reserve` 可能只增加逻辑大小、不进 raw 文件。这种被裁掉的尾部预留不能当成可写的占位字段。

`store.bytes` 接受字符串或 `bytes` 值。整数写入会检查宽度，值放不进目标宽度时报错。

## 计算校验和

`defer` 里可以声明 `const`、`let`，可以给局部 `let` 赋值，也可以用有界的 `while`。

```asm id=12-origin-2 bytes=0a0141424344
origin(0x5000)

checksum:
emit.u16(0)                   // 校验和占位

payload:
emit.bytes(b"ABCD")
payload_end:

defer {
    let cursor = payload
    let sum = 0

    // 逐字节累加 payload。
    while cursor < payload_end {
        sum = sum + load.u8(cursor)
        cursor = cursor + 1
    }

    store.u16(checksum, sum)
    assert(load.u16(checksum) == 266)
}
```

`266` 是 `0x010a`，最终输出：

```text
0a 01 41 42 43 44
```

`while` 受普通 Meta 循环的编译期迭代上限约束。`for` 目前不能放进 `defer`；需要扫字节时用边界清楚的 `while`。

## 查询最终区域信息

第 11 章那三个区域查询依赖最终布局，所以只能在 `defer` 里用：

```asm id=12-begin bytes=090000000c000000aa
region.begin("payload", 0x5000, 0)

file_size_field:
emit.u32(0)                   // 回填区域的文件大小
logical_size_field:
emit.u32(0)                   // 回填区域的逻辑大小

body:
emit.u8(0xaa)
reserve(3)                    // 尾部预留，不进文件

defer {
    store.u32(file_size_field, region_file_size(body))
    store.u32(logical_size_field, region_logical_size(body))

    assert(region_file_offset(body) == 0)
    assert(region_file_size(body) == 9)
    assert(region_logical_size(body) == 12)
}
```

输出：

```text
09 00 00 00 0c 00 00 00 aa
```

文件大小是 9：两个 `u32` 字段占 8 字节，`body` 占 1 字节。尾部 `reserve(3)` 不写进 raw 文件，所以不计入 `region_file_size`。逻辑大小是 12，因为尾部预留仍然占着逻辑地址范围。

三个查询分别是：

- `region_file_offset(address)`：包含该地址的区域最终从哪个 FOA 开始；
- `region_file_size(address)`：该区域最终写进 raw 文件的字节数；
- `region_logical_size(address)`：该区域最终占用的逻辑地址大小，含尾部预留。

它们不是写出阶段的"当前 FOA"查询。要当前 FOA 就用 `file_offset()` 或 `file_cursor_real()`；要最终区域大小就在 `defer` 里用 `region_file_*` 和 `region_logical_size`。

## 用过程登记回填

过程可以登记 `defer` 块，并把调用时传入的参数捕获进去：

```asm id=12-patch-u16 bytes=3412
fn patch_u16(address: u64, value: u64) {
    defer {
        store.u16(address, value)
    }
}

field:
emit.u16(0)

patch_u16(field, 0x1234)      // 登记回填，此刻还不写字节
```

最终输出：

```text
34 12
```

执行时机要注意：`patch_u16(...)` 在普通源码阶段就被调用了，调用时的 `address` 和 `value` 被保存进登记的 `defer` 块；真正写字节发生在最终布局稳定之后。

这种写法适合做类型明确的小型回填工具，比如 `patch_u32`、`patch_size_field`、`patch_checksum_field`。

## `defer` 里能写什么

`defer` 用于最终检查和回填。它可以写：

- `const`、`let` 和局部赋值；
- `if` / `else`；
- `while`、`break`、`continue`；
- `load.*`、`store.u8/u16/u32/u64`、`store.bytes`；
- `assert`、`print`、`warn`、`err`；
- 纯表达式和值函数；
- 标号、最终区域信息、已经稳定的输出字节。

它不能做任何改变布局的事。例如：

```text
defer {
    emit.u8(0x22)
}
```

会被拒绝。下面这些同样不允许放进 `defer`：

- 写 ISA 指令；
- 定义标号；
- `emit.*`、`db/dw/dd/...`；
- `reserve`、`align`、`pad`、`pad_to`；
- `origin`、`region.begin`、`output.section`、`output.org`、`virtual.begin`；
- 嵌套 `defer` 或 `late_layout`；
- 声明函数、结构体或加载源文件；
- 读外部文件。

需要空间就提前写占位，或者在 `late_layout` 里创建；`defer` 只能改已经存在的字节。

## 多个 `defer` 的执行顺序

`defer` 按登记顺序执行：

```asm id=12-u8 bytes=02
emit.u8(0)

defer {
    store.u8(0, 1)                // 先把第 0 字节改成 1
}

defer {
    store.u8(0, load.u8(0) + 1)   // 读到的是上一个 defer 写下的 1
}
```

第二个块能看到第一个块的修改，所以最终输出是：

```text
02
```

如果多个 `defer` 改同一个地址，后执行的块会看到前面的结果。不要把同一个字段拆到多个互相依赖的 `defer` 里，除非这个顺序就是你想要的格式规则。

`defer` 运行在这些步骤之后：

1. 普通源码处理；
2. `late_layout`；
3. 指令编码和布局松弛；
4. fixup 解析；
5. 最终文件字节生成；
6. fixup 修补。

所以 `defer` 看到的就是即将写出的最终映像：指令已经编码，引用已经解析，后期布局创建的字节也已经进入最终布局。

## `late_layout` 封存前新增真实布局

`late_layout` 用在"主源码已经登记完、但最终布局还没封存"的时候创建真实输出。

最简单的形式是追加字节：

```asm id=12-u8-2 bytes=102030
emit.u8(0x10)

// 两个块按登记顺序各执行一次，接在默认输出尾部。
late_layout {
    emit.u8(0x20)
}

late_layout {
    emit.u8(0x30)
}
```

`late_layout` 块按登记顺序各执行一次，默认从默认输出区域的尾部接着写。输出是：

```text
10 20 30
```

也就是说，默认行为是"接在当前默认输出尾部"。但 `late_layout` 不是只能往整个文件末尾追加：它允许调用输出区域 API，所以可以在块里显式打开一个真实区域，把晚生成的数据放到指定的 FOA。

例如先在虚拟区域里生成表，再在后期布局阶段把表放到指定的 raw 文件偏移：

```asm id=12-u32
table_foa_field:
emit.u32(0)                   // 回填表所在的 FOA
emit.bytes(b"HDR")

const table_origin: u64 = 0x8000
const table_foa: u64 = 0x10

virtual.begin(0)
table_tmp:
emit.bytes(b"TAB")            // 先在临时区域里把表拼出来
table_tmp_end:
virtual.end()

late_layout {
    // 建一个真实区域，把临时表拷到指定坐标。
    region.begin("late-table", table_origin, table_foa)
    emit.bytes(load.bytes(table_tmp, table_tmp_end - table_tmp))
}

defer {
    store.u32(table_foa_field, table_foa)
}
```

这里 `late_layout` 并没有"往最终文件里插入字节"，它是在最终映像生成前创建了一个真实区域：逻辑地址从 `0x8000` 开始，raw 文件偏移从 `0x10` 开始。最终文件怎么补洞、是否重叠、头字段是否一致，都由调用者的区域布局负责。

如果你已经用 `region.begin` / `output.section` / `output.org` 搭了类似 PE 的多段布局，那么 `late_layout` 里生成的表也可以放进某个明确的自定义区域，前提是你显式切到那个区域或给出正确的 FOA。只写 `emit.*` 时才是沿默认输出尾部继续。

标准 PE/COFF/ELF 优先用第 14 章的 `format.inc` 接口。直接写 `late_layout + region.begin` 更适合自定义格式，或者实现格式库里那些晚生成的符号表、字符串表、重定位表。

## `late_layout` 会影响尾部预留

`late_layout` 发生在最终布局之前，它新增的真实字节会参与 raw 文件布局。追加在尾部预留后面时，前面那段预留就变成了文件中间的零填充：

```asm id=12-u8-3 bytes=aa000000bb
emit.u8(0xaa)
reserve(3)

late_layout {
    emit.u8(0xbb)             // 尾部预留被夹在中间，必须写出来
}
```

最终输出：

```text
aa 00 00 00 bb
```

不想要这个结果，就不要在同一个区域的尾部预留后面直接追加真实字节。先用 `output.section` 裁掉尾部预留，或者用 `region.begin` 切到明确的目标区域。

## `late_layout` 里能写什么

`late_layout` 比普通源码窄得多：只接受 API 调用和 `if` 分支，没有普通局部作用域。

允许写：

- `emit.*`、`emit.bytes`、`emit.struct`、`db/dw/dd/...`；
- `reserve`、`pad`、`pad_to`、`align`；
- `origin`、`region.begin`、`region.file_align`；
- `output.section`、`output.org`；
- `virtual.begin`、`virtual.end`；
- `store.u8/u16/u32/u64`、`store.bytes`；
- `assert`、`print`、`warn`、`err`；
- `if` / `else`。

不允许写：

- `let` / `const` 声明；
- 赋值；
- `while` / `for`；
- 标号；
- ISA 指令文本；
- 函数、结构体、嵌套 `late_layout` 或 `defer`；
- 读外部文件或加载源模块。

需要计算的值、字节数组、表大小、目标 FOA，都应在普通源码阶段先计算好，再作为参数交给 `late_layout`。需要读文件时也在普通阶段读成 `bytes`，不要在 `late_layout` 或 `defer` 里读。

`late_layout` 只执行一次，它不是靠反复执行源码来收敛不稳定值的多遍模型。

## 三个阶段的分工

| 情况                                                                              | 用什么          |
| --------------------------------------------------------------------------------- | --------------- |
| 字节能按正常顺序写出来                                                            | 普通源码        |
| 需要标号、局部变量、函数、循环、读文件这些正常语言能力                            | 普通源码        |
| 必须等主源码登记完才知道要写哪些真实字节                                          | `late_layout` |
| 晚生成的表、字符串池、重定位记录需要进入最终文件                                  | `late_layout` |
| 需要显式放到某个 FOA，或沿默认输出尾部继续                                        | `late_layout` |
| 这些字节必须影响最终 raw size、logical size、偏移和回填                           | `late_layout` |
| 固定宽度占位字段需要最终值                                                        | `defer`       |
| 校验和需要完整的最终字节                                                          | `defer`       |
| 需要最终的`region_file_offset` / `region_file_size` / `region_logical_size` | `defer`       |
| 只修补已有字节，不创建空间                                                        | `defer`       |

几条防错规则：

- 不要用 `defer` 创建缺失的空间；
- 不要在 `late_layout` 里写需要局部变量和循环的逻辑；
- 尾部预留是否进文件要明确选择 `output.section` 或 `output.org`，不要靠猜；
- 构造标准 PE/COFF/ELF 时优先用 `format.inc`，不要手写重复的布局关系。

[返回目录](../language.md)
