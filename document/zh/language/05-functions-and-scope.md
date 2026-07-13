# 第5章：函数和作用域

## 函数封装编译时工作

函数封装可复用的编译时逻辑。可以计算值、输出数据，或组合多个底层操作。

XIRASM 有两种函数：

- **过程函数**执行操作，不产生表达式值。
- **返回值函数**计算值，用 `->` 声明返回类型。

两种都用 `fn`、参数和块体。函数在汇编时执行。声明函数不产生字节，只有调用过程函数或把计算结果传给输出接口才会产生输出。

注意别把2个作用一起用，比如又要返回值，又要当宏用。

## 过程函数

过程函数组合输出操作：

```asm
// 把传入字节及其后继值作为一组连续数据写出。
fn emit_pair(value: u8) {
    db(value);
    db(value + 1);
}

// 两次调用分别生成 02 03 和 08 09。
emit_pair(2);
emit_pair(8);
```

输出：

```text
02 03 08 09
```

没有 `->` 返回类型，就是过程函数。调用是语句，末尾加分号。

过程函数体可以包含声明、赋值、流程控制、数据输出、调用其他过程函数。适合封装重复的二进制记录、指令序列、表项和格式构建步骤。

过程函数本身不是值，不能用于初始化绑定：

```text
fn emit_marker() {
    db(0x90);
}

const marker = emit_marker()
```

报错，因为 `emit_marker()` 只执行操作，不返回值。

## 参数和实参

参数写在括号里：

```asm
// 连续写出 count 个相同字节。
fn emit_run(value: u8, count: u64) {
    // index 负责控制循环次数，循环体只需要使用 value。
    for index in range(0, count) {
        db(value);
    }
}

// 写出四个 cc 字节。
emit_run(0xcc, 4);
```

输出四个 `cc` 字节。`index` 控制循环次数，即使循环体里未使用它。

参数类型可以省略：

```asm
// 形参类型可以省略，调用时传入的值会绑定到对应形参。
fn add(left, right) -> u64 {
    return left + right;
}

// 计算 20 + 22，并把结果 2a 写成一个字节。
db(add(20, 22));
```

输出 `2a`。实参值绑定到对应参数。公开的辅助函数建议加类型注解，可明确约定并在调用处拦截不合适的实参。

实参按位置对应参数。调用时必须为每个参数提供一个实参。不支持默认实参。同一函数的参数名不能重复。每次调用有独立的参数绑定，互不影响。

## 返回值函数

函数需要产生表达式值时加 `-> type`：

```asm
// 把 value 向上对齐到 alignment 的整数倍。
fn align_up(value: u64, alignment: u64) -> u64 {
    return ((value + alignment - 1) / alignment) * alignment;
}

// 0x73 按 0x20 对齐后得到 0x80，再以双字节写出。
const header_size = align_up(0x73, 0x20)
dw(header_size);
```

函数返回 `0x80`，输出：

```text
80 00
```

`return` 末尾加分号。表达式转换为声明的返回类型。返回类型可以是整数、布尔值、字符串、字节序列等：

```asm
// 判断传入值是否等于一个 0x1000 字节的页大小。
fn is_page(value: u64) -> bool {
    return value == 0x1000;
}

// 返回固定的两个签名字节。
fn signature() -> bytes {
    return b"XR";
}

// 先检查计算结果，再写出签名字节。
assert(is_page(0x1000));
db(signature());
```

返回值函数可以用在任何能接受其返回类型的位置：声明、实参、条件、函数调用或更大的表达式。

## 返回规则和副作用

返回值函数必须执行到 `return`。末尾无返回值会报错：

```text
fn incomplete(value: u64) -> u64 {
    const doubled = value * 2
}

const result = incomplete(4)
```

返回值类型必须匹配：

```text
fn enabled() -> bool {
    return 1;
}

const result = enabled()
```

报错，整数不满足 `bool` 约定。

返回值函数用于计算，不能输出数据或产生其他副作用：

```text
fn bad_counter() -> u64 {
    db(1);
    return 1;
}

const result = bad_counter()
```

需要改变输出或布局时用过程函数，需要计算值时用返回值函数。

过程函数不声明返回类型，也不能返回值：

```text
fn emit_one() {
    return 1;
}

emit_one();
```

过程函数执行到末尾即结束。

## 函数局部作用域

参数和函数内的绑定只属于当前调用：

```asm
// 加上固定开销，并确保结果不小于 16。
fn adjusted_size(size: u64) -> u64 {
    const overhead = 4
    let result = size + overhead

    if result < 16 {
        result = 16
    }

    return result;
}

// 两次调用各自使用独立的局部绑定。
db(adjusted_size(3));
db(adjusted_size(20));
```

输出 `10 18`。每次调用创建新的 `size`、`overhead`、`result`，调用结束后这些名字不再可用。

函数内的块创建嵌套作用域，可遮盖外部名字：

```asm
// 使用嵌套作用域中的同名常量参与一次局部计算。
fn combine(value: u64) -> u64 {
    let result = value

    {
        // 此处的 value 只在这个代码块内表示常量 5。
        const value = 5
        result = result + value
    }

    return result;
}

// 参数值 3 与局部常量 5 相加，结果为 08。
db(combine(3));
```

输出 `08`。嵌套块中 `value` 指向局部常量 `5`。块结束后参数 `value` 重新可见。

中间计算用局部名字，避免临时状态泄漏到外部，多次调用互不干扰。

## 声明顺序

函数必须在调用前声明：

```asm
// 先声明函数，后面的源代码才能引用它。
fn add(left: u64, right: u64) -> u64 {
    return left + right;
}

// 调用已经可见的函数，并写出结果。
const answer = add(20, 22)
db(answer);
```

把调用移至声明前会报错，此时函数名尚未定义。

函数声明必须是顶层声明。不能将函数声明在另一个函数、循环、条件块或普通块内。相关函数在顶层相邻排列，后续源码调用。

第10章介绍如何通过包含文件将函数声明提供给另一个源文件。

## 递归和调用深度

返回值函数在有终止条件时可以递归调用自身：

```asm
// 递归计算从 value 到 1 的总和。
fn triangular(value: u64) -> u64 {
    // value 为零时停止递归。
    if value == 0 {
        return 0;
    }

    return value + triangular(value - 1);
}

// triangular(4) 计算 4 + 3 + 2 + 1，并写出 0a。
db(triangular(4));
```

输出 `0a`，即 `4 + 3 + 2 + 1` 的结果。

递归在编译时执行。递归深度应控制在一定范围内，终止条件必须明确。XIRASM 拒绝超过128层调用的函数链，防止失控递归。

遍历范围或集合用循环。计算本身具有递归结构且终止条件明确的用递归。

## 选哪种函数

| 需求             | 用这个         |
| ---------------- | -------------- |
| 输出字节或指令   | 过程函数       |
| 组合多个输出调用 | 过程函数       |
| 为表达式计算值   | 返回值函数     |
| 复用纯计算逻辑   | 返回值函数     |
| 临时名字不泄漏   | 两种均可       |
| 遍历范围或集合   | 通常用循环     |
| 递归计算         | 递归返回值函数 |

每个函数专注一件事。小计算函数易于组合，小过程函数使输出效果在调用处可见。

下一章介绍列表、映射、字符串和字节序列，供需要处理集合和文本的函数使用。

[返回语言指南](../language.md)
