# 第 13 章：Flat Binary 与自定义文件格式

XIRASM 默认生成 flat binary：输出文件只包含源码明确写出的指令、数据、填充、区域字节和后期布局字节。它不会自动添加 PE、ELF、COFF 头，也不会自动生成入口点、section 表、segment 表或重定位表。

这种模式适合：

- 引导扇区、固件映像、ROM 表；
- 协议消息、测试数据、资源容器；
- 私有二进制格式；
- 由其他程序加载的一小段机器码；
- 格式库内部用于生成头、表、字符串池的底层构造。

flat binary 不等于“没有结构”。你仍然可以用标号表示位置，用 `packed struct` 描述记录，用区域分开 RVA 和 FOA，用 `late_layout` 创建晚生成表，用 `defer` 回填最终字段。

## 原始机器码

最简单的 flat 文件就是指令字节本身：

```asm
x86.use64();

entry:
    mov eax, 42
    ret
```

输出：

```text
b8 2a 00 00 00 c3
```

这里没有操作系统文件头，也没有“入口点字段”。`entry` 只是 XIRASM 标号。加载这些字节的程序必须自己知道 ISA、模式、装载地址和调用约定。

## 文件头加 Payload

自定义格式通常先写固定头，再写 payload：

```asm
emit.bytes(b"RAW1");
emit.u16(1);
emit.u16(0);

payload:
emit.bytes(b"ABC");
```

输出：

```text
52 41 57 31 01 00 00 00 41 42 43
```

前四字节是签名，第一个 `u16` 是版本号，第二个 `u16` 保留，后面是 payload。没有额外格式声明；源码写出顺序就是文件顺序。

## 用 `packed struct` 描述记录

二进制记录需要固定字段和固定宽度时，用 `packed struct` 把格式写清楚：

```asm
packed struct ChunkHeader {
    kind: u16
    size: u16
}

emit.struct(ChunkHeader {
    kind: 1,
    size: 3,
});
emit.bytes(b"ABC");
```

输出：

```text
01 00 03 00 41 42 43
```

`packed struct` 不插入隐式对齐间隙，适合描述磁盘格式、网络格式和紧凑表项。只有文件格式本身要求普通结构体的对齐和尾部填充时，才用普通 `struct`。

重复记录可以封装成函数：

```asm
fn emit_record(tag: u8, value: u32) {
    emit.u8(tag);
    emit.u32(value);
}

emit_record(1, 0x11223344);
emit_record(2, 0xaabbccdd);
```

输出：

```text
01 44 33 22 11 02 dd cc bb aa
```

函数负责保持记录写法一致；最终文件仍然按调用顺序生成。

## 用 `defer` 回填文件头

不要手工维护大小、偏移和校验和。先写固定宽度占位字段，再用标号和最终字节回填：

```asm
origin(0);

magic:
emit.bytes(b"XIF1");
size_field:
emit.u32(0);
payload_foa_field:
emit.u32(0);
checksum_field:
emit.u32(0);

payload:
emit.bytes(b"OK!!");
payload_end:

defer {
    store.u32(size_field, payload_end - magic);
    store.u32(payload_foa_field, payload - region_base());
    store.u32(checksum_field, load.u8(payload) + load.u8(payload + 1));

    assert(load.bytes(magic, 4) == b"XIF1");
    assert(load.u32(size_field) == 20);
    assert(load.u32(payload_foa_field) == payload - magic);
    assert(load.u32(checksum_field) == 0x9a);
}
```

输出：

```text
58 49 46 31 14 00 00 00 10 00 00 00 9a 00 00 00 4f 4b 21 21
```

这个例子没有硬编码总大小和 payload 偏移。头或 payload 改了，`defer` 会按最终布局写回新值。

本例从 `origin(0)` 开始，逻辑地址差值正好等于文件内相对偏移。只要你开始使用多个区域，这个关系就不一定成立。

## 明确字段要的是 RVA 还是 FOA

自定义格式里最容易出错的是把逻辑地址和 raw 文件偏移混用。写字段前先问清楚它要哪一个：

- 需要逻辑地址 / RVA：用标号值，或用标号相减得到逻辑距离；
- 需要当前 raw 文件偏移 / FOA：写出阶段用 `file_offset()` 或 `file_cursor_real()`；
- 需要某个区域最终 FOA：在 `defer` 里用 `region_file_offset(address)`；
- 需要 raw size：在 `defer` 里用 `region_file_size(address)`；
- 需要 virtual size / logical size：在 `defer` 里用 `region_logical_size(address)`。

例子：

```asm
region.begin("header", 0x1000, 0);
emit.bytes(b"HDR0");

output.section("payload", 0x2000);
payload:
emit.bytes(b"DATA");

defer {
    assert(payload == 0x2000);
    assert(region_file_offset(payload) == 4);
}
```

raw 文件仍然紧凑：

```text
48 44 52 30 44 41 54 41
```

`payload` 的逻辑地址是 `0x2000`，但它在文件里从 FOA `4` 开始。除非格式明确规定二者相等，否则不要从逻辑地址推导 FOA。

## 表示文件间隙和 file-free 尾部

`reserve` 是否进入 raw 文件，取决于它是不是仍然处在区域尾部：

- 中间间隙：后面还有真实字节，reserve 会写成文件里的零；
- 尾部预留：只增加逻辑大小，可以不占 raw 文件空间。

```asm
region.begin("image", 0x5000, 0);

emit.bytes(b"HDR0");
file_size_field:
emit.u32(0);
logical_size_field:
emit.u32(0);

emit.u8(0xaa);
reserve(3);
emit.u8(0xee);
reserve(8);

defer {
    store.u32(file_size_field, region_file_size(file_size_field));
    store.u32(logical_size_field, region_logical_size(logical_size_field));

    assert(load.u32(file_size_field) == 17);
    assert(load.u32(logical_size_field) == 25);
}
```

raw 文件只有 17 字节：

```text
48 44 52 30 11 00 00 00 19 00 00 00 aa 00 00 00 ee
```

中间 3 字节 reserve 因为后面有 `0xee`，所以进入 raw 文件。最后 8 字节 reserve 仍在区域尾部，只把 logical size 增加到 25，不增加 raw size。

这正是 BSS、未初始化尾部、节尾虚拟空间这类格式字段的基础：文件记录已初始化前缀，剩余地址范围由加载器或消费程序提供。

## `late_layout`：晚生成但仍参与布局

只有在真实字节必须等主源码登记完之后才能创建时，才用 `late_layout`。最简单的例子是追加尾部：

```asm
total_size:
emit.u32(0);
emit.bytes(b"DATA");

late_layout {
    emit.bytes(b"END!");
}

defer {
    store.u32(total_size, region_file_size(total_size));
    assert(load.u32(total_size) == 12);
}
```

输出：

```text
0c 00 00 00 44 41 54 41 45 4e 44 21
```

这里 `late_layout` 写出的 `END!` 会参与最终 raw size。`defer` 能看到它，并把总大小回填到开头。

如果 `late_layout` 里只写 `emit.*`，它就是从默认输出区域的尾部继续。若晚生成内容应该落到某个自定义表区、数据区或指定 FOA，就必须在块里显式切区域：

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

这不是在最终文件里“插入”字节，而是在最终映像封存前创建一个真实区域。它可以放到文件尾，也可以放到你指定的 FOA；关键是你必须自己保证区域不重叠、头字段一致、raw size/logical size 符合格式规则。

如果只是回填头部已有字段，用 `defer`。如果缺的是变长表、字符串池、重定位记录等真实字节，就要在普通源码或 `late_layout` 里创建它们。

## 用断言保护自定义格式

自定义格式应该把关键不变量写成断言：

- 签名、版本和标志字段正确；
- 偏移字段指向预期区域；
- 计数等于实际写出的记录数；
- raw size 和 logical size 符合格式规则；
- 校验和覆盖正确字节范围；
- 尾部 reserve 是否进入文件符合预期。

`defer` 中的断言检查最终输出字节，包括已经编码的指令、已解析的 fixup、`late_layout` 生成的字节和所有回填结果。断言失败时汇编停止，避免产出表面上有文件头、实际上字段已经错位的文件。

大小回填和对应断言通常放在同一个 `defer` 块里，这样字段来源和验证条件靠在一起。

## 推荐组织顺序

小型自定义格式可以按这个顺序写：

1. 声明常量、记录类型和辅助函数；
2. 写固定文件头，占位字段先写 0；
3. 写 payload 和普通表；
4. 用 `late_layout` 创建确实需要晚出的真实字节；
5. 用 `defer` 回填大小、偏移、校验和，并断言最终结果。

格式变复杂后仍然保持同样分工：

- 源码和函数决定写哪些记录；
- 标号和区域描述逻辑地址、FOA 和大小；
- `virtual.begin` 用于临时生成和测量；
- `late_layout` 创建必须参与最终布局的晚生成字节；
- `defer` 只回填和验证稳定后的字段。

不要把一堆硬编码偏移散落在源码里。把固定格式常量放在一起；把记录写出封装成函数；把最终值统一由标号、区域查询和断言推导出来。

## 什么时候用格式接口

flat 输出能表达任意字节，但不代表应该手写标准可执行文件或目标文件格式。PE、COFF、ELF 还要维护文件头、section/segment 表、权限、导入、导出、重定位、BSS、对齐和加载器规则。

标准格式优先用 `format.inc` 包装层。语言指南只解释底层机制：RVA/FOA、区域、虚拟输出、`late_layout` 和 `defer`。完整普通用法见[《格式教程》](../format-tutorial.md)。只有在实现新的格式接口或手写私有格式时，才需要直接使用本章这些底层能力。

[返回目录](../language.md)
