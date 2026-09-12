# 第 11 章：输出区域与虚拟数据

写最简单的 flat binary 时，“地址”和“文件偏移”是一样的（标号值 / 偏移值）：第一个字节的地址是 0，文件偏移也是 0，往后一起长，这在汇编器里叫地址跟进，反正中文就这么理解就对了。

如果你不用自己构造可执行格式，比如自定义格式，或不想专研OS那些可执行格式，那么可以跳过这部分，只了解`origin`/`here`这俩个API就行。

只要开始写 PE、ELF、COFF，或者自己定一种二进制格式，这个假设就不成立了：

- `.text` 运行时可能映射到 `0x401000`，但在文件里从一个很小的偏移开始；
- BSS 要占住一段运行时地址，却不能把那一大段零都写进文件；
- 文件头里的 RVA、raw pointer、raw size、virtual size，要等各段都写完了才能回填；
- 有些表要先在临时空间里生成、测量、改字节，最后才复制到真正的输出里。

XIRASM 用四个互相独立的量来描述这些差别：**逻辑地址（RVA）**、**raw 文件偏移（FOA）**、**最终写进文件的字节**，以及**临时虚拟输出**。

## RVA 与 FOA

一个真实输出区域有四个量：

| 名称                   | 含义                                                                                                                  |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `origin`             | 这个区域的逻辑地址基准。标号地址从这里开始计算。写 PE 时通常对应 RVA 或 image base + RVA，写 ELF 时通常对应虚拟地址。 |
| `file_offset`（FOA） | 这个区域在 raw 文件里的起始偏移。                                                                                     |
| `logical size`       | 这个区域占掉的逻辑地址范围。`reserve` 计入这个大小。                                                                    |
| `file size`          | 这个区域最后真正写进 raw 文件的字节数。区域尾部的 `reserve` 可以不计入。                                               |

这四个量互相代替不了。改 `origin` 不会顺手补上文件里的填充；改 FOA 也不会挪动标号地址。PE 头里 `VirtualAddress`、`PointerToRawData`、`VirtualSize`、`SizeOfRawData` 容易写错，就是因为它们分别来自这四个量。

写布局时常用这几个查询。注意它们回答的是**两个不同的坐标系**：逻辑地址那一套（和标号同一个坐标系），和文件偏移那一套：

| 查询                        | 它回答的问题                                                                  |
| --------------------------- | ----------------------------------------------------------------------------- |
| `region_base()`           | 这个区域的逻辑地址基准是多少（标号地址从这个基准开始计算）。                            |
| `here()`                  | 当前逻辑地址是多少。作用相当于传统汇编器里的`$`。                           |
| `file_offset()`           | 已经写进 raw 文件的字节数是多少。**它就是下一个真字节要落的文件位置**。 |
| `file_cursor_real()`      | 同上，和`file_offset()` 取值完全一样。                                      |
| `file_cursor_potential()` | 如果把尾部那段还没落地的 `reserve` 也计入，下一个文件位置会是多少。        |
| `tail_reserve_size()`     | 当前区域末尾还有多少个保留字节没进 raw 文件。                                 |

`file_offset()` 和 `file_cursor_real()` 是一回事，两个名字都在用。真正有区别的是后两个：**`file_cursor_potential()` 把待落的预留计入，`file_offset()` 不计入。**

## 用 `print` 看中间值

上面这几个查询在不同阶段的取值不一样，光看文档容易记混。`print` 能把值直接打出来，是排查布局问题时最顺手的工具：

- 它**不写输出文件**，只往诊断里加一条 `note`；
- 值按内容打印：整数给十进制数值（不是字节），字符串给文本，`bytes` 给 `b"..."`，`list` 和 `map` 带长度展开。

`print` 可以接多个实参，它们按顺序拼在一条 note 里。`origin(0x4000)`、写一个字节、再 `reserve(3)` 之后：

```asm id=11-origin
origin(0x4000)

emit.u8(0xaa)
reserve(3)                 // 逻辑上占 3 字节，文件里还没有它们

print("here", here())
print("file_offset", file_offset())
print("cursor_real", file_cursor_real())
print("cursor_potential", file_cursor_potential())
print("tail_reserve", tail_reserve_size())
```

装配时打出来的是：

```text
note: here 16388
note: file_offset 1
note: cursor_real 1
note: cursor_potential 4
note: tail_reserve 3
```

读法：`here` 是逻辑地址 `0x4004`，`file_offset` 是文件偏移 `1`——**两个数在各自的坐标系里都表示"当前位置"**，所以本来就该不一样，不能拿数值直接比。`file_cursor_potential()` 的 `4` 意思是"如果那 3 个预留字节也写进文件，下一个文件位置会是 4"。

`warn` 报 warning，`err` 报 error 并让汇编失败；`print` 只是 note，不影响结果。

这些接口主要给自定义格式和格式库内部用。写普通 PE/COFF/ELF 时先看 `format.inc` 的包装层，大部分 RVA/FOA 关系它已经替你维护好了。

## `origin` 只改逻辑地址

`origin(address)` 改当前区域的逻辑地址基准，不动文件偏移：

```asm id=11-origin-2 bytes=aa
// 区域逻辑起点设为 0x4000；文件里仍然从 0 开始。
origin(0x4000)

start:
emit.u8(0xaa)

assert(region_base() == 0x4000)
assert(label_addr("start") == 0x4000)
assert(here() == 0x4001)      // 写出一个字节后逻辑地址前进一格
assert(file_offset() == 1)
```

输出只有一个字节：

```text
aa
```

`start` 的地址是 `0x4000`，文件里却只写了一个字节。`origin` 用来给 flat 输出设装载地址，或者在某个区域里挪动标号地址基准。它不会创建新区，也不会把文件位置跳到 `0x4000`。

## `region.begin` 指定 RVA 和 FOA

`region.begin(name, origin, file_offset)` 开始一个新的真实输出区域，同时给出这个区域的逻辑地址基准和起始 FOA。三个参数都要写：参数个数不对会报 `InvalidApiArity`。

```asm id=11-begin bytes=4844000000000000000000000000000044415441
// header 的逻辑地址从 0x1000 开始，raw 文件偏移从 0 开始。
region.begin("header", 0x1000, 0)

header:
emit.bytes(b"HD")

// payload 有自己的逻辑地址，从 FOA 0x10 开始。
region.begin("payload", 0x2000, 0x10)

payload:
emit.bytes(b"DATA")

assert(label_addr("header") == 0x1000)
assert(label_addr("payload") == 0x2000)
```

`header` 占 FOA 0 和 1，`payload` 从 FOA 0x10 开始。中间那一段没有区域写入，flat 文件会补零：

```text
48 44 00 00 00 00 00 00 00 00 00 00 00 00 00 00
44 41 54 41
```

`region.begin` 不是“插入字节”，也不是 PE/ELF/COFF 的 section 声明。它只说明：接下来的输出属于一个新区域，这个区域的逻辑地址和 raw 文件偏移分别是多少。

区域之间是否按 FOA 递增、是否重叠、是否留洞，由调用者自己负责。写标准格式时不要拿 `region.begin` 去拼 PE/ELF/COFF 的文件头；优先用 `format.inc`，只在手写自定义格式或实现格式辅助函数时才直接管理区域。

## `reserve` 与尾部预留

写真实字节时，逻辑地址和 raw 文件尾部一起前进：

```asm id=11-u8
emit.u8(0xaa)

assert(file_cursor_real() == 1)          // 一个字节真的进了文件
assert(file_cursor_potential() == 1)
assert(tail_reserve_size() == 0)         // 没有待落的预留
```

`reserve(n)` 不一样：它推进逻辑地址，但只要这段预留还在区域末尾，XIRASM 就不会立刻把它写成文件里的零：

```asm id=11-u8-2
emit.u8(0xaa)      // 文件里 1 个字节
reserve(3)         // 逻辑地址前进 3 格，文件没动

assert(here() == 4)                      // 逻辑上已经占 4 字节
assert(file_cursor_real() == 1)          // 文件里还是 1 个字节
assert(file_cursor_potential() == 4)     // 这 3 字节也可以选择保留
assert(tail_reserve_size() == 3)
```

这时区域逻辑上占 4 字节，raw 文件里只有 `aa`。尾部那 3 字节可以被裁掉，也可以在后面选择保留成文件里的零填充。

如果 `reserve` 之后又写了真实字节，它就不再是尾部预留，而是文件中间的间隙，必须进 raw 文件：

```asm id=11-u8-3 bytes=aa000000bb
emit.u8(0xaa)
reserve(3)
emit.u8(0xbb)      // 夹在两个真实字节中间，3 个零必须写出来

assert(file_cursor_real() == 5)
assert(file_cursor_potential() == 5)
assert(tail_reserve_size() == 0)         // 已经不是尾部预留了
```

文件内容：

```text
aa 00 00 00 bb
```

这条规则是写 BSS、section 尾部 padding、raw size / virtual size 的基础：尾部预留增加逻辑大小；只有它被后面的真实字节夹住，或者你主动选择保留，才会变成 raw 文件里的零。

## `output.org` 保留尾部预留

`output.org(name, origin)` 从**逻辑偏移**开始下一个区域。它把前面区域末尾那段还没落地的 `reserve` 一起计入，于是预留变成 raw 文件里真实的零填充：

```asm id=11-u8-4 bytes=4100000042
emit.u8(0x41)
reserve(3)

// 逻辑偏移是 4，所以 next 从 FOA 4 开始，前面三个预留字节被写出来。
output.org("next", 0x2000)
emit.u8(0x42)
```

输出是：

```text
41 00 00 00 42
```

## `output.section` 裁掉尾部预留

`output.section(name, origin)` 从**文件偏移**开始下一个区域。它不看逻辑偏移，所以前一个区域末尾那段还没进文件的 `reserve` 直接被裁掉：

```asm id=11-u8-5 bytes=4142
emit.u8(0x41)
reserve(3)

// 文件偏移是 1，所以 next 从 FOA 1 开始，尾部预留不写进文件。
output.section("next", 0x2000)
emit.u8(0x42)
```

第一个区域的逻辑大小仍然是 4，raw 文件大小只有 1。新区域接在 FOA 1 后面，所以输出是：

```text
41 42
```

BSS 一类区域要的正是这个：内存里要有地址范围，文件里不要写一大段零。

注意裁掉的是**区域尾部**那段预留。如果 `reserve` 后面还跟着真实字节，它早就是文件中间的间隙了，这段不会被删。

两者的区别在于新区域从哪里接：

| 操作               | 接在哪个位置                                  | 尾部预留的去向     |
| ------------------ | --------------------------------------------- | ------------------ |
| `output.org`     | 当前**逻辑偏移**（`here()` 那个位置） | 变成文件里的零填充 |
| `output.section` | 当前**文件偏移**（真实写到的位置）      | 被裁掉，不进文件   |

两者都会给新区域设置新的 `origin`。`origin` 只影响标号地址，不影响上面这个选择。

## `region.file_align` 只对齐 raw size

`region.file_align(alignment)` 对齐的是当前区域最终写入 raw 文件的大小。它不推进逻辑地址，也不会把尾部预留变成逻辑内容：

```asm id=11-begin-2 bytes=41424300000000005a
region.begin("first", 0x1000, 0)

emit.bytes(b"ABC")     // 3 个真实字节
reserve(13)            // 推到逻辑地址 16，但文件里还是 3 字节

assert(here() == 0x1010)
assert(file_cursor_real() == 3)
assert(file_cursor_potential() == 16)

// 裁掉尾部预留后，把 raw size 对齐到 8。
region.file_align(8)

region.begin("second", 0x2000, 8)
emit.u8(0x5a)
```

`ABC` 三个真实字节参与 raw size 对齐，XIRASM 补 5 个零，把第一个区域的 raw size 补到 8。第二个区域从 FOA 8 开始：

```text
41 42 43 00 00 00 00 00 5a
```

第一个区域的逻辑大小仍然是 16，因为 `reserve(13)` 已经推进了逻辑地址。`region.file_align` 改的是 raw 文件大小，不是 RVA 范围。

对齐值必须是非零的 2 的幂。调用 `region.file_align` 之后，当前区域的文件输出就结束了；要接着写真实字节，得开始另一个区域。

它和 `align` 的区别：

- `align` 是普通输出操作，会推进逻辑地址；如果形成文件间隙，就要写出填充字节。
- `region.file_align` 是区域收尾操作，只对齐这个区域的 raw size。

需要“RVA 也往前走”时用 `align`；只需要“raw size 对齐到 FileAlignment”时用 `region.file_align`。

## 虚拟区域

虚拟区域用来临时组装、测量、读取或改写字节。它有自己的逻辑地址和字节内容，但不会自动写进最终文件：

```asm id=11-begin-3 bytes=45322310
// 在逻辑地址 0x3000 创建一个临时区域。
virtual.begin(0x3000)

table:
emit.u32(0x11223344)              // 区域里先有 44 33 22 11
store.u32(table, load.u32(table) ^ 0x01010101)   // 原地异或成 45 32 23 10
const encoded: bytes = load.bytes(table, 4)      // 取出四字节快照

virtual.end()

// 只有显式复制出来的字节才进主输出。
emit.bytes(encoded)
```

变换后复制到主输出的是：

```text
45 32 23 10
```

对照一下：那个临时区域刚创建时里面是 `44 33 22 11`，异或之后才变成上面这四个字节；主输出里只有这最后的四字节，`44 33 22 11` 从没进过文件。

虚拟区域适合做资源表、导出表、字符串池、校验数据这类临时构造。里面可以写数据、`reserve`、`align`、定义标号、写 ISA 指令，也可以用 `load.*` 和 `store.*` 读写这些临时字节。

`virtual.begin()` 也可以不带参数，这时逻辑地址取**当前地址**：

```asm id=11-bytes
emit.bytes(b"AB")

// 不给 origin：临时区域从当前地址接着算。
virtual.begin()
emit.bytes(b"CT")
virtual.end()

emit.bytes(b"D")       // 这里写出：41 42 44
```

虚拟区域里的 `CT` 没有进文件，主输出只有 `AB` 和 `D`。参数只能给 0 个或 1 个，给两个会报 `InvalidApiArity`。

它有三条边界：

- 每个 `virtual.begin` 都要有对应的 `virtual.end`。
- 虚拟区域里不能启动主输出区域；`output.section` 和 `output.org` 只能在回到真实输出之后调用。
- 需要回填的指令在虚拟区域里保持"未回填"：`emit.bytes` 拷贝的是虚拟字节的**快照**，而快照发生在回填之前，所以里面还是编码时的占位值。scratch 里放的是带引用的代码时，要用 `region.place` 把整个区域落位（见下）。

虚拟区域里的地址不是最终文件位置。要让虚拟内容进文件，可以用 `emit.bytes(...)` 或格式库的复制流程拷贝字节，也可以用 `region.place` 把整个区域落位。

虚拟区域和普通区域一样，字节只存在于逻辑地址上。写到尾部预留那一段会失败：

```asm id=11-u8-6 error=this store writes 1 byte at 0x2, but the finished output image holds 1 byte; a reserved tail is not in the file (InvalidApiArgument)
emit.u8(0xaa)
reserve(3)                  // 尾部预留：逻辑上占 3 字节，文件里只有 1 字节

defer {
    store.u8(2, 0x55)       // 地址 2 落在那段预留里，写不进去
}
```

诊断会把地址和文件长度都说清楚：

```text
error: this store writes 1 byte at 0x2, but the finished output image holds 1 byte; a reserved tail is not in the file (InvalidApiArgument)
```

## `region.place` 把虚拟内容落进文件

`region.place(label, origin, file_offset)` 把 `label` 所在的虚拟区域变成真实输出区域，坐标由调用者给出。和 `emit.bytes` 不同，它保留这个区域里的指令、标号和引用，所以 scratch 里写的跳转和调用会由正常的 fixup 流程按**落位后的地址**解析：

```asm id=11-use64 bytes=90000000000000000000000000000000e8fb7fffffe9f6ffffff
x86.use64()

main_target:
emit.u8(0x90)

virtual.begin(0x9000)

gen_start:
call main_target          // 目标在虚拟区域外面，落位时才解析
jmp gen_start             // 自跳，同样是落位后解析

virtual.end()

late_layout {
    region.place("gen_start", 0x8000, 0x10)
}
```

虚拟区域从逻辑地址 `0x8000`、FOA `0x10` 落位。输出的头 16 个字节是主输出里那个 `0x90` 加上补齐，接着是落位过来的 `call` 和 `jmp`：

```text
90 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
e8 fb 7f ff ff
e9 f6 ff ff ff
```

`call` 的位移 `0x7ffb` 指向落位后的 `main_target`（`0x0000`），`jmp` 的位移 `0xfffffff6` 指回落位后的 `gen_start`（`0x8010`）。两者都由落位后的地址计算得到，源文件里没有手写偏移。

## `load.*` / `store.*` 只在当前活动区域

`load.*` 和 `store.*` 读写的是当前活动区域里已经生成的字节：

```asm id=11-u8-7 bytes=42
emit.u8(0x5a)

// 先读出原值，再原地改掉：first 留下的是改写前的 0x5a。
const first: u64 = load.u8(0)
store.u8(0, 0x42)

assert(load.u8(0) == 0x42)
assert(first == 0x5a)
```

```text
42
```

`load.u8(0)` 读出的是改写前的值 `0x5a`，`store.u8(0, 0x42)` 把第 0 个字节改掉。最终写出的只有 `42`。

地址是相对于当前活动区域起点的偏移。虚拟区域的字节要靠 `load.*` 读出来，或者用 `region.place` 落位。

## 最终区域信息只在收尾阶段查询

这几个查询只有在收尾阶段才有确定的答案：

| 查询                             | 返回什么                             |
| -------------------------------- | ------------------------------------ |
| `region_file_offset(address)`  | `address` 所在区域最终的起始 FOA。 |
| `region_file_size(address)`    | 这个区域最终写进 raw 文件的字节数。  |
| `region_logical_size(address)` | 这个区域最终的逻辑大小，含尾部预留。 |

用它们回填文件头。例如 PE 的 section 头需要 `PointerToRawData`、`SizeOfRawData`、`VirtualSize`，ELF 的程序头需要 `p_offset`、`p_filesz`、`p_memsz` 这类字段，这些都要等布局定下来之后再写。

在普通输出阶段调用这几个查询会失败，因为最终映像那时还不存在。要等 `defer`（第 12 章）里再查。

[返回语言目录](../language.md)
