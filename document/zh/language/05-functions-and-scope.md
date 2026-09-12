# 第 5 章：函数与作用域

## 函数的两种形式

函数是命名的编译期代码块，供后续调用。它有两种形式：

- **过程**执行动作，不产生值；
- **返回值函数**用 `->` 声明结果类型。

两者都用 `fn`、参数和代码块。函数本身不写出字节，字节在它被调用、或者返回值交给写输出的接口时才产生。

## 过程

过程没有 `->`，调用它就是一条语句：

```asm id=05-emit-pair
fn emit_pair(value: u8) {
    db(value)          // 函数体里可以放任何调用处能放的东西
    db(value + 1)
}

emit_pair(2)
emit_pair(8)
```

过程不是值，它的用途是执行生成数据的逻辑。把它赋给绑定会被拒绝：

```asm id=05-emit-marker error=undefined name in this expression: emit_marker()
// 过程没有返回值，所以不能写进 const。
fn emit_marker() {
    db(0x90)
}

const marker = emit_marker()
```

```text
bad.xir:5:1: error: undefined name in this expression: emit_marker()
```

## 参数与实参

参数按位置接收实参，没有默认值：

```asm id=05-emit-run
fn emit_run(value: u8, count: u64) {
    for index in range(0, count) {
        db(value)      // 每轮一个字节
    }
}

emit_run(0xcc, 4)
```

每次调用有自己的一套参数绑定，互不影响。参数的类型注解可以省略：

```asm id=05-add
fn add(left, right) -> u64 {
    return left + right
}

db(add(20, 22))        // 42 = 0x2a
```

建议在函数上方写上注释，说明每个参数是什么：没有类型标注时，隔一段时间就看不懂这段逻辑了。

## `let` 参数

参数默认只读；加 `let` 前缀后传的是调用者的绑定本身，而不是它的值：

```asm id=05-set-entry
// plan 带 let：函数改的是调用者那个 map 本身。
fn set_entry(let plan: map, address: u64) {
    map.set_mut(plan, "entry", address)
}

let image: map = map.new()
set_entry(image, 0x401000)

// 回到调用者这边看，改动确实落在 image 上。
assert(map.get(image, "entry") == 0x401000)
```

实参必须是普通的 `let` 绑定：

```asm id=05-set-entry-2 error=mutable function argument must resolve to a let binding
fn set_entry(let plan: map, address: u64) {
    map.set_mut(plan, "entry", address)
}

// image 是 const，不能交给 let 参数改写。
const image: map = map.new()
set_entry(image, 0x401000)
```

```text
bad.xir:6:1: error: mutable function argument must resolve to a let binding
```

字面量和临时表达式都不行：

```asm id=05-touch error=mutable function argument must be a direct let binding
fn touch(let a: u64) {
    db(0)
}

// 5 是字面量，没有绑定可改。
touch(5)
```

```text
bad.xir:5:1: error: mutable function argument must be a direct let binding
```

同一次调用不能把同一个绑定传给两个 `let` 参数：

```asm id=05-touch-2 error=mutable function arguments cannot alias the same binding
fn touch(let a: u64, let b: u64) {
    db(0)
}

// 同一个 shared 传给两个 let 参数，两处会互相覆盖。
let shared = 1
touch(shared, shared)
```

```text
bad.xir:6:1: error: mutable function arguments cannot alias the same binding
```

`let` 参数要靠语句调用写回调用者，因此返回值函数不能带 `let` 参数：

```asm id=05-bump error=the function declaration or call is not valid (InvalidMetaFunction)
// 带 -> 的声明不能配 let 参数：写回调用者要靠语句调用，而这里返回的是值。
fn bump(let value: u64) -> u64 {
    return value + 1
}
```

```text
bad.xir:1:1: error: the function declaration or call is not valid (InvalidMetaFunction)
```

## 返回值函数

写 `->` 类型后，函数产生一个表达式值：

```asm id=05-align-up
fn align_up(value: u64, alignment: u64) -> u64 {
    return ((value + alignment - 1) / alignment) * alignment
}

const header_size = align_up(0x73, 0x20)
dw(header_size)        // 0x80
```

结果会转换到声明的返回类型，返回类型可以是任何普通的编译期值：

```asm id=05-is-page
// 返回类型可以是 bool，也可以是 bytes 这类非整数值。
fn is_page(value: u64) -> bool {
    return value == 0x1000
}

fn signature() -> bytes {
    return b"XR"
}

assert(is_page(0x1000))
db(signature())         // 这里写出：58 52
```

凡是能接受该结果类型的表达式位置，都可以使用返回值调用：声明、实参、条件、另一个调用，或者更大的表达式。

## 返回规则

返回值函数必须走到 `return`：

```asm id=05-incomplete error=function incomplete declares a return value, but its body ended without a return statement
// 算了一个值却没写 return，所以函数没有结果可交。
fn incomplete(value: u64) -> u64 {
    const doubled = value * 2
}

const result = incomplete(4)
```

```text
bad.xir:1:1: error: function incomplete declares a return value, but its body ended without a return statement
```

返回的值必须满足声明的类型：

```asm id=05-enabled error=function enabled declares a bool return value, but this return statement produces a integer
// 声明说要 bool，这里返回的是整数字面量 1。
fn enabled() -> bool {
    return 1
}

const result = enabled()
```

```text
bad.xir:2:5: error: function enabled declares a bool return value, but this return statement produces a integer
```

返回值函数是计算用的辅助工具：可以用局部绑定、控制流和别的返回值调用，但不能写出输出，也不能改变布局：

```asm id=05-bad-counter error=a value-returning function cannot emit instructions or change layout; declare it without a return type to run it as a procedure (SideEffectInValueFunction)
// 声明了 -> 却写出输出：这条限制把两种形式分开了。
fn bad_counter() -> u64 {
    db(1)
    return 1
}

const result = bad_counter()
```

```text
bad.xir:2:5: error: a value-returning function cannot emit instructions or change layout; declare it without a return type to run it as a procedure (SideEffectInValueFunction)
```

正是这条限制划分了两种形式：需要改变输出或布局时用过程，调用者需要值时用返回值函数。过程不声明返回类型，也不能返回值：

```asm id=05-emit-one error=the function declaration or call is not valid (InvalidMetaFunction)
// 过程不声明返回类型，所以它不能 return 一个值。
fn emit_one() {
    return 1
}

emit_one()
```

```text
bad.xir:2:5: error: the function declaration or call is not valid (InvalidMetaFunction)
```

## 函数局部作用域

参数和函数体内声明的绑定都属于这一次调用(每次都独立)：

```asm id=05-adjusted-size
fn adjusted_size(size: u64) -> u64 {
    const overhead = 4
    let result = size + overhead

    if result < 16 {
        result = 16
    }

    return result
}

db(adjusted_size(3))    // 16
db(adjusted_size(20))   // 24
```

每次调用都会新建 `size`、`overhead` 和 `result`，它们都不会在这次调用之后留下。实参在参数绑定存在之前、在调用者的作用域里求值，所以 `pair(b, a)` 不会因为某个参数名叫 `a` 而改变第二个实参的读法。

函数体内的代码块会嵌套，可以遮蔽外层名字，而外层作用域仍然可写：

```asm id=05-combine
fn combine(value: u64) -> u64 {
    let result = value

    {
        const value = 5      // 遮蔽参数
        result = result + value
    }

    return result
}

db(combine(3))          // 3 + 5
```

## 声明顺序

函数必须声明在第一条调用它的语句之前：

```asm id=05-add-2 error=undefined name in this expression: add(20, 22)
// add 在后面才声明，这里先用它。
const answer = add(20, 22)

fn add(left: u64, right: u64) -> u64 {
    return left + right
}

db(answer)
```

```text
bad.xir:1:1: error: undefined name in this expression: add(20, 22)
```

声明都在顶层。嵌在函数体里的声明会在该函数体被 lowering 时报错：

```asm id=05-outer error=the function declaration or call is not valid (InvalidMetaFunction)
// 函数里再声明函数：外层被调用时就会报错。
fn outer() {
    fn inner() {
        db(1)
    }
    inner()
}

outer()
```

```text
bad.xir:2:5: error: the function declaration or call is not valid (InvalidMetaFunction)
```

第 10 章会讲包含文件如何把声明提供给另一个源文件。

## 递归与调用深度

计算有明显基准情况时，返回值函数可以调用自己：

```asm id=05-triangular
fn triangular(value: u64) -> u64 {
    if value == 0 {
        return 0
    }

    return value + triangular(value - 1)
}

db(triangular(4))       // 4 + 3 + 2 + 1
```

递归同样在汇编期间执行，所以必须保持浅。调用链达到 128 层会被拒绝：

```asm id=05-down error=an expression in this statement is not valid (InvalidExpression)
// 递归到 128 层，超过调用深度上限。
fn down(n: u64) -> u64 {
    if n == 0 {
        return 0
    }

    return down(n - 1) + 1
}

db(down(128))
```

```text
bad.xir:5:5: error: an expression in this statement is not valid (InvalidExpression)
```

## 指令形式的宏

宏把一行源码起个名字。调用它就照处理器的写法写：行首写宏名，后面跟操作数：

```asm id=05-twice
macro twice(dst, src) {
    mov dst, src
    mov dst, src
}

x86.use64()
twice eax, ebx          // 这里写出：89 d8 89 d8
```

前端先在行首认出助记符 `twice`，它是宏名，于是把**整行**交给宏体处理，编码器根本看不到这一行。宏体里那两行 `mov dst, src` 才是真正交给编码器的指令。

替换只发生在**指令操作数**位置，而且只看位置、不看内容：

- 替换进去的文本不会被再看一遍，所以它里面即使写着另一个参数名，也不会被当成参数再替换一次；
- 引号只是操作数里的一部分字符。写 `spell "reg"` 时，参数接收的是 `"reg"` 这五个字符（含引号），往里填的永远是整个操作数；
- 行首的助记符和参数替换无关：参数名恰好和某条指令同名，也不会把那一行改掉。

宏和函数在参数上不一样。函数调用时，实参先计算出值再传进去；宏调用时，参数接收的是**调用处写的那段源码文本**：

| 调用处写的 | 参数接收的 |
| --- | --- |
| `twice eax, ebx` 里的 `eax` | 文本 `eax` |
| `twice eax, ebx` 里的 `ebx` | 文本 `ebx` |

上面这个宏只把文本填进指令，文本本身是什么意思，这个宏并不关心。要计算出一个值，就得让参数把文本当表达式求值——这需要另一种东西来装它，就是 `operand`。

## `operand`：捕获的源码

`operand` 是一个值类型，装的是**一段源码文本，外加写下这段文本时能看见的绑定**。带上绑定是为了之后再求值：文本里的名字要按调用处的定义去读，不能按宏体里的定义读。

`operand` 有两个取法：

- `operand.text(value)` 取原样的拼写，不求值；
- `operand.eval(value)` 把那段文本当 Meta 表达式求值，得到它计算出的值。

要自己实现一条指令的编码，就用 `operand.eval` 把参数计算出值：

```asm id=05-byte
macro byte(value) {
    const n: u64 = operand.eval(value)   // 按调用处的绑定求值
    emit.u8(n)
}

const LIMIT: u64 = 7
byte LIMIT + 1          // 这里写出：08
byte (LIMIT + 2)        // 这里写出：09
```

第一次调用里，`value` 接收的文本是 `LIMIT + 1`，按调用处的 `LIMIT = 7` 求值得到 8。第二次调用写的是 `byte (LIMIT + 2)`，参数文本是 `(LIMIT + 2)`——注意外层那对括号是 Meta 的普通括号，参与运算，所以求值得到 9。写 `byte LIMIT + 2` 不带括号也一样，逗号才是操作数的分界。

`emit.u8(n)` 把一个字节写进当前输出。写输出的接口分两族：

- `db`、`dw`、`dd`、`dq` 把宽度写在助记符上，收整数并按宽度检查范围；其中 `db` 还收字符串和字节序列，`db("AB")` 写出 `41 42`，而 `dw` 及以上只收整数。
- `emit` 族把宽度写成类型：`emit.u8`、`emit.u16`、`emit.u32`、`emit.u64` 只收整数并按宽度检查范围，`emit.u8(0x1234)` 报 `InvalidApiInteger`；`emit.bytes` 收字节序列或字符串；`emit.f32`、`emit.f64` 收浮点数。没有有符号的 `emit.i*`。

宏的参数没有类型注解，也没有默认值。写 `byte(7)` 会报 `macro calls use instruction syntax without parentheses`，因为那样写像函数调用；要带括号就得写成 `byte (7)`，中间留一个空格。末尾的参数写成 `...name`，它把剩下的操作数全部收成一个列表。同名可以同时有一个固定参数个数的版本和一个 `...name` 版本，个数对得上时用固定版本；对不上则报 `MacroArityMismatch`。

AArch64 指令库（`arm/a64-macros.inc`）就是这样建起来的：那里的指令能按 AArch64 汇编文本书写，是因为每一条都被写成了宏。要给自己的一套编码规则做成指令的样子，做法相同。

`operand.eval` 求值用的是**捕获那段文本时可见的绑定**，不是宏体里的绑定：

```asm id=05-emit-one-2
macro emit_one(value) {
    const n: u64 = operand.eval(value)
    emit.u8(n)
}

const LIMIT: u64 = 7
emit_one LIMIT + 1      // 这里写出：08
```

宏体里再声明一个同名 `const` 也改不了它。捕获的文本带着调用处的作用域，宏体的名字不在其中：

```asm id=05-shadowed
macro shadowed(value) {
    const LIMIT: u64 = 100               // 对捕获的表达式不可见
    const n: u64 = operand.eval(value)
    emit.u8(n)
}

const LIMIT: u64 = 7
shadowed LIMIT + 1      // 这里写出：08，宏体里的 LIMIT 改不了它
```

这条调用同样写出 `08`。同一个道理让宏可以安全地复用调用处的名字：宏体里出现什么名字，都不会改变调用处那段文本的读法。

不要求值、只要原本的拼写时，用 `operand.text`：

```asm id=05-spell
macro spell(value) {
    emit.bytes(operand.text(value))
}

spell 1 + 2             // 这里写出：31 20 2b 20 32
```

写出 `31 20 2b 20 32`，也就是 `"1 + 2"` 这五个字符。

## 在指令操作数里写参数

指令操作数位置需要的是文本，所以在那里直接写参数名，由宏把它替换成捕获的文本：

```asm id=05-load
macro load(reg, source) {
    mov reg, source
}

x86.use64()
const OFFSET: u64 = 7
load rax, OFFSET        // 编码器收到的是 `mov rax, 7`
```

编码器收到的就是上面注释里那句文本。反过来，`operand.eval` 产出的是值，只能用在 API 实参和 `const` 初始化这类需要值的地方；把它写在操作数位置上，那里已经没有东西可供求值：

```asm id=05-bad error=macro operand text operand.eval(7) cannot be encoded as an operand; bind it to a const first, as in `const value: u64 = operand.eval(text)` (UnresolvedFixup)
// 操作数位置要的是文本，operand.eval 产出的是值 —— 位置不对。
macro bad(value) {
    mov rax, operand.eval(value)
}

x86.use64()
bad 7
```

```text
bad.xir:2:5: error: macro operand text operand.eval(7) cannot be encoded as an operand; bind it to a const first, as in `const value: u64 = operand.eval(text)` (UnresolvedFixup)
```

## 收多个操作数

参数可以只收一个操作数，也可以把末尾的 `...name` 写成变参，把剩余操作数收成一个列表：

```asm id=05-bytes
macro bytes(...values) {
    for item in values {
        emit.u8(operand.eval(item))
    }
}

bytes 1, 2, 3           // 这里写出：01 02 03
```

`operand` 上还有两个辅助函数：

- `operand.slice(value, start, end)` 取捕获文本的一段字节范围，并检查越界；
- `operand.split(value)` 在顶层逗号处切分，引号和配对的 `()[]{}` 原样保留，所以 `(a, b)` 和 `"a,b"` 都算作一整段。

两者都保留每一段的捕获绑定：

```asm id=05-first-three
macro first_three(arg) {
    const head: operand = operand.slice(arg, 0, 3)
    emit.bytes(operand.text(head))
}

first_three abcdef      // 这里写出：61 62 63
```

写出 `61 62 63`。宏之间可以互相调用：

```asm id=05-byte-2
macro byte(value) {
    const n: u64 = operand.eval(value)
    emit.u8(n)
}

macro twice(dst, src) {
    mov dst, src
    mov dst, src
}

macro bytes(...values) {
    for item in values {
        byte item
    }
}

x86.use64()
twice eax, ebx          // 这里写出：89 d8 89 d8
bytes 1, 2, 3           // 这里写出：01 02 03
```

写出 `89 d8 89 d8` 和 `01 02 03`。

绑定到 operand 的标识符在转发时带着它原本的捕获，循环和辅助函数里的操作数局部变量同样如此；混合表达式的每个片段各自保留自己的绑定。由 `operand.eval` 调用的函数使用第一个片段的捕获作用域，`here()` 这类位置内建函数使用该片段的捕获位置，每次 `operand.eval` 都重新求值一次。

## 定义位置与执行次数

宏在顶层定义，并且要先定义后使用，包括经过 `import` 引入的情况。名字区分大小写，可以带点分隔的段。

宏体使用普通的多行代码块语法，可以包含 Meta 变量、控制流、过程、指令和收尾块注册。宏体不返回值；`break` 和 `continue` 不能跳进调用者的循环；已保存的 `defer` 和 `late_layout` 体内不能定义或调用宏；宏也不能绕过返回值函数的副作用限制。

每次真正到达的调用在 lowering 期间只执行一次，布局、松弛、编码和收尾都不会重跑宏体。宏与函数共用 128 层调用深度，宏调用另有每个 lowering 上下文累计 100,000 次的上限；一次调用最多 256 个操作数、64 层操作数分隔符；捕获环境最多链到 128 层，超出报告 `MacroCaptureDepthExceeded`。捕获会复制当时可见的值绑定，把操作数和大量集合长期放在一起有内存代价；不再需要原始语法时，把它求值成普通值存起来。

宏里的静态标号仍是模块标号。要私有标号，用 `sym.unique` 造名字、用 `label.define` 定义。`isa(text)` 绕过宏查找直接提交原生指令。

## AArch64 指令宏库

导入 `arm/a64-macros.inc` 之后，AArch64 指令按汇编文本直接写，由宏库负责编码：

```asm id=05-import
// 导入之后，这些助记符就都按宏解析，直接写汇编文本即可。
import("arm/a64-macros.inc")
const OFFSET: u64 = 16
fadd v0.4s, v1.4s, v2.4s             // 浮点 SIMD 加法
movi v3.4s, #255, lsl #8             // 立即数：按 lane 移位铺开
ldr x2, [sp, #OFFSET]                // 基址 + 编译期算出的字节偏移
ld2 {v31.s, v0.s}[3], [sp], x4       // 结构访存：一次取两个 lane，带写回
ldr x5, data                         // 标号作为地址操作数
data:
emit.u64(0)
```

库由生成器产出：`include/arm/a64/generated/manifest.json` 里登记了 **778 个宏助记符、4360 条指令形式**，覆盖浮点与 Advanced SIMD、lane/copy/table、立即数与转换、访存与结构访存、标量整数、分支和系统指令。

分支支持延后解析标签，条件分支写成 `b.eq target` 这种形式；`adrp` 计算目标页与指令所在页之间的差值。系统寄存器接受 `nzcv` 这类固定名称，也接受 `S3_3_C4_C2_0` 这种通用拼写。

加密与扩展指令同样在库内，例如 `aese`/`aesd`（AES）、`sha256h`（SHA）、`crc32b`（CRC）、`ldadd`/`cas`/`swp`（LSE 原子操作）、`sdot`/`udot`（点积）、`bfdot`/`bfcvtn`（BF16）、`smmla`/`ummla`（I8MM）、`paciza`（指针认证）、`bti`（BTI）、`irg`/`stg`（MTE）。点积的成组 lane 写成 `v2.4b[index]` 或 `v2.2h[index]`，对应直接描述符如 `a64_lane("v2.4b", index)`。

**尚不包含** SVE/SME 和 A32/T32。

导入之后，同名助记符在整个 lowering 上下文里都归宏处理，不按原生 target 隔离。混合 ISA 源码可以导入 `arm/a64.inc` 改用直接 API，直接调用接收描述符列表：

```asm id=05-import-2
import("arm/a64.inc")
a64_ldr(list.of(a64_reg("x0"), a64_mem("sp", 16)))   // 无论原生 target 是什么，写出的都是 A64 编码
```

立即数表达式沿用 Meta 算术，捕获操作数保留调用者绑定。包装层先检查操作数形状，再求值并检查各指令的寄存器角色、范围、缩放、对齐和写回重叠约束。访存基址允许 X0-X30 或 SP；寄存器偏移的 UXTW/SXTW 使用 W 寄存器，LSL/SXTX 使用 X 寄存器。

literal load 的 `#expression` 表示字节位移；裸标号在布局后解析，捕获地址表达式可写为 `label_addr(data) + ADDEND`。直接调用使用 `a64_rel(displacement)`、`a64_target(name)` 或 `a64_address(address)`。延后目标通过收尾块解析并检查范围，不会重新执行宏；`_word` 函数接收已解析描述符并返回编码。

[返回语言指南](../language.md)
