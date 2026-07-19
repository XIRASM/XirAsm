# 第 11 章：输出区域与虚拟数据

写最简单的 flat binary 时，可以把“地址”和“文件偏移”当成同一件事：第一个字节地址是 0，FOA 也是 0，后面一起增长。

但只要开始写 PE、ELF、COFF，或者手写自己的二进制格式，这个假设马上就会出错：

- `.text` 运行时可能映射到 `0x401000`，但它在文件里通常从较小的 raw 偏移开始；
- BSS 需要占一段运行时地址，却不应该把整段零都写进文件；
- 文件头里的 RVA、raw pointer、raw size、virtual size 往往要等各段都写完后才能回填；
- 有些表要先在临时空间里生成、测量、改字节，再复制到真正的输出里。

所以本章只讲一件事：XIRASM 怎样把 **逻辑地址 / RVA**、**raw 文件偏移 / FOA**、**最终进入文件的字节** 和 **临时虚拟输出** 分开管理。

## 先分清 RVA 和 FOA

一个真实输出区域至少有四个量：

| 名称 | 说明 |
| --- | --- |
| `origin` | 区域的逻辑地址基准。标号地址从这里开始算；写 PE 时通常对应 RVA 或 image base + RVA，写 ELF 时通常对应虚拟地址。 |
| `file_offset` / FOA | 区域在 raw 文件中的起始偏移。 |
| `logical size` | 区域占用的逻辑地址范围。`reserve` 会计入这个大小。 |
| `file size` | 区域最终实际写进 raw 文件的字节数。尾部 `reserve` 可以不计入这个大小。 |

这四个量不能互相代替。改 `origin` 不会自动插入文件填充；改 FOA 也不会改变标号地址。PE 里的 `VirtualAddress`、`PointerToRawData`、`VirtualSize`、`SizeOfRawData` 之所以容易写错，就是因为它们分别来自这几类信息。

写布局时常用这些查询：

| 查询 | 返回什么 |
| --- | --- |
| `region_base()` | 当前区域的 `origin`，也就是标号地址的基准。 |
| `here()` | 当前逻辑地址。 |
| `file_offset()` | 当前已经确定的 raw 文件偏移；尾部只有 `reserve` 时，它仍停在真实文件尾部。 |
| `file_cursor_real()` | 下一个已经确定会写进 raw 文件的位置。可以把它当成“当前真实 FOA”。 |
| `file_cursor_potential()` | 如果把当前尾部 `reserve` 也保留成文件里的零填充，下一个 FOA 会是多少。 |
| `tail_reserve_size()` | 当前区域末尾还有多少 `reserve` 尚未进入 raw 文件。 |

注意：`file_cursor_potential()` 只是 API 名。实际判断很简单：它等于“真实 FOA + 尾部还没落地的 reserve”。

这些 API 主要给自定义格式和格式库内部使用。普通 PE/COFF/ELF 用法优先看 `format.inc` 包装层；它会替你维护大部分 RVA/FOA 关系。

## `origin` 只改逻辑地址

`origin(address)` 修改当前区域的逻辑地址基准，不修改文件偏移。

```asm
// 把当前输出区域的逻辑起点设为 0x4000。
origin(0x4000);

start:
emit.u8(0xaa);

assert(region_base() == 0x4000);
assert(label_addr("start") == 0x4000);
assert(here() == 0x4001);
assert(file_offset() == 1);
```

输出只有一个字节：

```text
aa
```

这里 `start` 的地址是 `0x4000`，但文件里仍然只写了一个字节。`origin` 适合 flat 输出设置装载地址，或者在某个区域内调整标号地址基准。它不会创建新区，也不会把文件位置跳到 `0x4000`。

## `region.begin` 显式指定 RVA 和 FOA

`region.begin(name, origin, file_offset)` 开始一个新的真实输出区域。它同时指定：

- `origin`：这个区域的逻辑地址基准；
- `file_offset`：这个区域在 raw 文件中的起始 FOA。

```asm
// header 的逻辑地址从 0x1000 开始，raw 文件偏移从 0 开始。
region.begin("header", 0x1000, 0);

header:
emit.bytes(b"HD");

// payload 有自己的逻辑地址，并从 FOA 0x10 开始。
region.begin("payload", 0x2000, 0x10);

payload:
emit.bytes(b"DATA");

assert(label_addr("header") == 0x1000);
assert(label_addr("payload") == 0x2000);
```

`header` 占 FOA 0 和 1，`payload` 从 FOA 0x10 开始。中间没有真实区域写入的 raw 范围，最终 flat 文件会补零：

```text
48 44 00 00 00 00 00 00 00 00 00 00 00 00 00 00
44 41 54 41
```

`region.begin` 不是“插入字节”，也不是 PE/ELF/COFF 的 section 声明。它只告诉 XIRASM：接下来的输出属于一个新区域，并且这个区域的逻辑地址和 raw 文件偏移是多少。

区域之间是否按 FOA 递增、是否重叠、是否留洞，调用者自己负责。写标准格式时不要直接散用 `region.begin` 拼 PE/ELF/COFF 头；优先使用 `format.inc`，只在手写自定义格式或实现格式辅助函数时直接管理这些区域。

## `reserve` 推进逻辑大小，但尾部可以不进文件

写真实字节时，逻辑地址和 raw 文件尾部都会前进：

```asm
emit.u8(0xaa);

assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 1);
assert(tail_reserve_size() == 0);
```

`reserve(n)` 不一样。它推进逻辑地址，但如果它还在区域尾部，XIRASM 不会立刻把它写成文件里的零：

```asm
emit.u8(0xaa);
reserve(3);

assert(here() == 4);
assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 4);
assert(tail_reserve_size() == 3);
```

这时区域逻辑上已经占 4 字节，但 raw 文件只有 `aa` 一个字节。尾部 3 字节可以被裁掉，也可以在后续选择中变成文件里的零填充。

如果 `reserve` 后面又写真实字节，它就不再是“尾部预留”，而是文件中间的间隙，必须进入 raw 文件：

```asm
emit.u8(0xaa);
reserve(3);
emit.u8(0xbb);

assert(file_cursor_real() == 5);
assert(file_cursor_potential() == 5);
assert(tail_reserve_size() == 0);
```

文件内容：

```text
aa 00 00 00 bb
```

这条规则是写 BSS、section 尾部 padding、raw size / virtual size 的基础：尾部 reserve 增加逻辑大小；只有它被后续真实字节夹在中间，或你主动选择保留它时，才会变成 raw 文件里的零。

## `output.section` 裁掉尾部 reserve

`output.section(name, origin)` 用“当前真实 FOA”开始下一个区域。也就是：前一个区域末尾还没有进入文件的 `reserve` 会被裁掉。

```asm
emit.u8(0x41);
reserve(3);

// next 从 FOA 1 开始，前面的尾部 reserve 不写入文件。
output.section("next", 0x2000);
emit.u8(0x42);
```

第一个区域的逻辑大小仍然是 4，但 raw 文件大小只有 1。新区域接在 FOA 1，所以输出是：

```text
41 42
```

这就是 BSS 一类区域常要的行为：内存里要有地址范围，文件里不要写一大段零。

`output.section` 只裁掉“还在区域尾部”的 reserve。已经位于文件中间的间隙不会被删除。

## `output.org` 保留尾部 reserve

`output.org(name, origin)` 用“把尾部 reserve 也算进去后的 FOA”开始下一个区域。也就是：前一个区域末尾的 `reserve` 会变成 raw 文件里的零填充。

```asm
emit.u8(0x41);
reserve(3);

// next 从 FOA 4 开始，前面的三个 reserve 字节保留为文件间隙。
output.org("next", 0x2000);
emit.u8(0x42);
```

输出是：

```text
41 00 00 00 42
```

所以二者的选择可以直接按 FOA 说：

| 操作 | 新区域从哪里开始 |
| --- | --- |
| `output.section` | 从真实 raw 文件尾部开始，尾部 reserve 不进文件。 |
| `output.org` | 从 reserve 之后开始，尾部 reserve 作为零填充保留在文件里。 |

二者都会给新区域设置新的 `origin`。`origin` 只影响标号地址，不影响上面这个 FOA 选择。

## `region.file_align` 只对齐 raw size

`region.file_align(alignment)` 对齐的是当前区域最终写入 raw 文件的大小。它不推进逻辑地址，也不会把尾部 reserve 变成逻辑内容。

```asm
region.begin("first", 0x1000, 0);

emit.bytes(b"ABC");
reserve(13);

assert(here() == 0x1010);
assert(file_cursor_real() == 3);
assert(file_cursor_potential() == 16);

// 裁掉尾部 reserve 后，把 raw size 对齐到 8。
region.file_align(8);

region.begin("second", 0x2000, 8);
emit.u8(0x5a);
```

`ABC` 三个真实字节参与 raw size 对齐，XIRASM 补 5 个零，把第一区域的 raw size 补到 8。第二区域从 FOA 8 开始：

```text
41 42 43 00 00 00 00 00 5a
```

第一区域的逻辑大小仍然是 16，因为 `reserve(13)` 已经推进了逻辑地址。`region.file_align` 改的是 raw 文件大小，不是 RVA 范围。

对齐值必须是非零的 2 的幂。调用 `region.file_align` 后，当前区域的文件输出已经结束；继续写真实字节前，应开始另一个区域。

它和 `align` 的区别很重要：

- `align` 是普通输出操作，会推进逻辑地址；如果形成文件间隙，就会写填充字节。
- `region.file_align` 是区域收尾操作，只对齐该区域的 raw size。

需要“RVA 也往前走”时用 `align`；只需要“raw size 对齐到 FileAlignment”时用 `region.file_align`。

## 虚拟区域是临时输出，不自动进文件

虚拟区域用于临时组装、测量、读取或改写字节。它有自己的逻辑地址和字节内容，但不会自动写进最终文件。

```asm
// 在逻辑地址 0x3000 创建一个临时区域。
virtual.begin(0x3000);

table:
emit.u32(0x11223344);
store.u32(table, load.u32(table) ^ 0x01010101);
const encoded: bytes = load.bytes(table, 4)

virtual.end();

// 只有显式复制出来的字节才会进入主输出。
emit.bytes(encoded);
```

虚拟区域里最初是：

```text
44 33 22 11
```

变换后复制到主输出的是：

```text
45 32 23 10
```

虚拟区域适合做资源表、导出表、字符串池、校验数据等临时构造。里面可以写数据、`reserve`、`align`、定义标号、写 ISA 指令，也可以用 `load.*` 和 `store.*` 读写这些临时字节。

但它有两个边界：

- 每个 `virtual.begin` 必须有对应的 `virtual.end`。
- 虚拟区域里不能启动主输出区域；`output.section` 和 `output.org` 只能在回到真实输出后调用。

虚拟区域里的地址不是最终文件位置。要让虚拟内容进入文件，必须像上面的例子一样显式 `emit.bytes(...)` 或用格式库提供的复制流程。

## 省略虚拟 origin：从当前位置的逻辑地址开始

`virtual.begin()` 可以不传参数。省略时，虚拟区域的逻辑地址从外围区域当前的 `here()` 开始。

```asm
origin(0x4000);
emit.u8(0xaa);

// 当前 here() 是 0x4001，虚拟区域也从这里开始算地址。
virtual.begin();

scratch:
emit.u16(0x1234);
const copied: bytes = load.bytes(scratch, 2)

virtual.end();

emit.bytes(copied);
```

`scratch` 的逻辑地址是 `0x4001`，但虚拟输出不会替换主输出，也不会推进主输出位置。最终文件是：

```text
aa 34 12
```

这种写法适合“按当前地址假装组装一段内容，然后只取它的字节结果”的场景。

## 最终区域信息只能在收尾阶段查询

写出阶段能知道“当前正在写到哪里”，但不能查询所有区域最终的 raw size / logical size。原因很简单：后面的区域、尾部 reserve、文件对齐、late layout 和最终收尾都可能影响最终布局事实。

区域最终事实只能在收尾阶段查询：

| 查询 | 返回什么 |
| --- | --- |
| `region_file_offset(address)` | 包含该地址的区域最终从哪个 FOA 开始。 |
| `region_file_size(address)` | 该区域最终写进 raw 文件的字节数。 |
| `region_logical_size(address)` | 该区域最终占用的逻辑地址大小，包含尾部 reserve。 |

这三个查询通常用于回填文件头。例如 PE section header 里的 `PointerToRawData`、`SizeOfRawData`、`VirtualSize`，或者 ELF program header 里的 `p_offset`、`p_filesz`、`p_memsz`，都应该等布局稳定后再写。

如果在普通写出阶段调用这些查询，会因为没有最终 output image 而报错。下一章介绍收尾阶段：它可以读取最终布局、回填已经存在的字节、做断言和校验，但不能再改变布局。

## 怎么选

只设置 `origin`：

- 单个 flat 输出需要非零装载地址；
- 文件偏移和逻辑位置仍然同步推进。

用 `region.begin`：

- 逻辑地址和 FOA 都已经明确；
- 你正在手写自定义格式，或者实现 `format.inc` 这类格式接口。

用 `output.section`：

- 新区域应该紧接真实 raw 文件尾部；
- 前一区域尾部 reserve 只表示逻辑大小，不应该占文件空间。

用 `output.org`：

- 新区域应该从 reserve 之后开始；
- 前一区域尾部 reserve 必须变成文件里的零填充。

用 `region.file_align`：

- 区域 raw size 需要按文件格式对齐；
- 不希望改变逻辑地址范围。

用虚拟区域：

- 需要临时生成、测量、读取或改写一段字节；
- 这些临时字节只有显式复制后才进入最终文件。

一句话总结：

- 标号、`here()`、`origin` 讲的是逻辑地址 / RVA；
- `file_offset()`、`file_cursor_real()` 讲的是已经确定的 FOA；
- `file_cursor_potential()` 只是在问“如果尾部 reserve 也进文件，FOA 会到哪里”；
- `region_file_*` 和 `region_logical_size` 只能在最终布局稳定后用于回填和检查。

下一章介绍收尾处理：读取稳定布局、回填字节、计算校验和、验证映像，但不再改变布局。

[返回目录](../language.md)
