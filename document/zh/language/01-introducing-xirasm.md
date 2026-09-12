# 第 1 章：认识 XIRASM

## 指令与编译期代码

XIRASM 源文件混写两类行：**处理器指令**用所选指令集的汇编语法，**编译期代码**在汇编过程中计算值、决定输出内容。

```asm id=hello target=x86-64 bytes=b82a000000c3
x86.use64()                 // 编译期调用：选定 64 位 x86 编码

const answer: u32 = 40 + 2  // 汇编时计算

entry:                      // 标号记录当前地址，不写出字节
    mov eax, answer         // 指令；`answer` 成为立即操作数
    ret
```

一行属于哪种形态由这一行本身决定，与文件无关：

| 这一行要做什么         | 写法                                      |
| ---------------------- | ----------------------------------------- |
| 编码一条处理器指令     | 汇编指令行                                |
| 在汇编期间计算一个值   | 编译期表达式                              |
| 重复或选择要生成的内容 | 编译期控制流                              |
| 向输出写入字节         | `db`、`dw`、`dd`、`dq` 等数据调用 |
| 描述文件格式结构       | `format.inc` 调用                       |

## 汇编第一个程序

保存为 `hello.xir` 并运行：

```text
xirasm hello.xir
```

命令行只打印一行摘要，字节写入 `hello.bin`：

```text
assembled output (6 bytes, 2 instruction fragments, target x86-64)
```

```text
b8 2a 00 00 00 c3
```

前五个字节编码 `mov eax, 42`，最后一个字节编码 `ret`。标号不写出任何字节。

这样汇编得到的输出是 flat binary（平坦二进制）：源码写出的字节本身，不带操作系统文件头。格式接口在第 14 章介绍，PE、COFF 和 ELF 的完整内容见[格式教程](../format-tutorial.md)。

## 编译期代码向输出写入字节

编译期代码在 XIRASM 构造输出时运行，不是生成出来的程序里运行的代码。下面的循环每轮写一个字节：

```asm id=emit-range target=x86-64
const count: u8 = 4

for value in range(0, count) {   // 0 <= value < count，汇编期间展开
    db(value)                    // 每轮一个字节
}
```

```text
00 01 02 03
```

## 源码规则

一行放一条语句，行到行尾就结束。同一行写两个调用是错误，保存为 `bad.xir` 会报：

```asm id=two-calls-one-line target=x86-64
db(1); db(2)
```

```text
bad.xir:1:1: error: a line holds one statement: this call is followed by more text, so write the rest on its own line (TrailingTextAfterCall)
```

`;` 结束的是一条编译期语句。它后面不能再有别的内容，也不是必须写，本指南一律不写：

```asm id=semicolon-forms target=x86-64 bytes=0102
db(1);   // 可以写
db(2)    // 同一个语句，没写
```

`;` 不结束指令，所以指令行末尾不能带分号：

```asm id=isa-trailing-semicolon target=x86-64
nop;
```

```text
bad.xir:1:1: error: ISA text does not end with a semicolon
```

行注释、标号和代码块：

- `//` 到行尾是注释，可出现在任何语句之后：指令、调用、声明、赋值、标号、代码块声明头、控制语句都一样；引号内的 `//` 仍是普通文本。
- 标号以 `:` 结尾。
- 代码块用 `{` 和 `}`。函数、`if`、`while`、`for` 的声明头在同一行以 `{` 结尾；孤立的 `else` 或不匹配的 `}` 是错误。
- 调用和复合值在括号或花括号未闭合时可以跨行书写。

编译期代码与指令在同一份文件里交错出现：

```asm id=emit-marker target=x86-64 bytes=7f03b803000000c3
x86.use64()

fn emit_marker(value: u8) {   // 编译期函数：写出两字节标记
    db(0x7f, value)
}

const marker: u8 = 3
emit_marker(marker)           // 调用在汇编期间执行，不在运行时

start:                        // 从这里开始是指令
    mov eax, marker
    ret
```

两类内容写进同一份 8 字节输出。

[返回语言指南](../language.md)
