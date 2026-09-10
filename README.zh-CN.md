# XIRASM

[English](README.md) | [项目网站](https://xirasm-site.pages.dev/) | [版本更新](https://xirasm-site.pages.dev/#updates)

**一款同时支持 x86、AArch64、RISC-V 与 SPIR-V 的现代汇编器：直接写汇编，
直接生成 Windows、Linux、macOS 与 Android 上的可用产物；需要时，再用
编译期语言把构建过程变成程序。**

XIRASM 使用自然的 ISA 指令文本，可以直接生成 flat binary、Windows PE/COFF、
Linux ELF、macOS Mach-O 与完整 SPIR-V 模块，也能顺带把包住这些代码的 Android
APK 一起构建出来。简单程序就是普通汇编；只有在项目需要生成代码、复用格式逻辑
或精确控制二进制布局时，才需要使用类型化的编译期语言。

- **四类指令集：** x86 16/32/64 位模式、AArch64、RV32/RV64 与 SPIR-V 1.6。
- **直接得到可用产物：** EXE、DLL、共享库、目标文件、Mach-O 镜像、flat binary、
  SPIR-V 模块，以及可直接安装的 Android APK，而不是停在中间表示或实验输出。
- **能落到真机上的 AArch64：** `arm/a64-macros.inc` 提供 AArch64 指令文本，格式层
  再把编码结果带进 ELF64 可执行文件、PIE、目标文件与 Android 共享库，以及
  PE64/COFF64 镜像和 Mach-O arm64 的可执行文件、dylib 与目标文件，并各自带上
  对应的重定位和导入桩。
- **不需要 Java 构建链的 Android：** APK 写出器生成 ZIP 容器、二进制
  `AndroidManifest.xml`，以及由资源目录编译出的 `resources.arsc`，并能装载同一份
  源码汇编出的 NativeActivity 共享库。`@android:style/Theme.DeviceDefault` 这类
  平台资源 ID 来自生成好的框架目录表。
- **现代元编程能力：** 类型值、函数、集合、模块、结构化控制流和精确源码诊断，
  不再依赖脆弱的文本宏堆叠。
- **从源码到原生程序的路径足够短：** 工程模板可直接生成 Windows/Linux 项目，
  常规 PE、COFF、ELF 与 Mach-O 由高层格式接口完成，不要求用户手工拼出每个文件头。

## 下载

每个版本同时提供预编译包，只有要修改 XIRASM 本身时才需要自己装工具链：

- Windows x86-64（ZIP）与 Linux x86-64（静态链接 TAR.GZ）；
- macOS Apple Silicon（TAR.GZ）；
- VS Code 扩展与语言服务器（VSIX）。

从[项目网站](https://xirasm-site.pages.dev/#downloads)或
[GitHub Release](https://github.com/XIRASM/XirAsm/releases/latest)获取当前版本，
Release 正文列出每个包的 SHA-256。每个包内含可执行文件、`include` 库、测试用例以及
中英文文档。

## 几步生成原生程序

使用 Zig 0.17 构建 XIRASM：

```text
zig build -Doptimize=ReleaseSafe
```

将生成的 `xirasm` 加入 `PATH`，然后创建并构建一个原生项目：

```text
xirasm init hello --isa x86-64 --os windows --abi msvc
cd hello
xirasm build
```

Linux 项目改用 `--os linux --abi sysv`。生成目录已经包含源码和
`xirasm.toml`，后续进入目录执行 `xirasm build` 即可。

CLI 子命令写在选项之前：应使用 `xirasm build --timings`，不要写成
`xirasm --timings build`。

## 汇编仍然是汇编

标号与处理器指令保持自然写法。只有真正适合自动生成的部分才使用编译期代码：

```asm
x86.use64();

fn emit_square_table(count: u8) {
    for value in range(0, count) {
        dd(value * value);
    }
}

const answer: u32 = 40 + 2;

entry:
    mov eax, answer
    ret

table:
emit_square_table(4);
```

函数与循环只在汇编阶段运行，最终产物中只有机器码和生成的数据；没有运行时解释器，
也不需要把每条指令写成函数调用。

最小的 flat binary 源码可以只有几行：

```asm
x86.use64();

entry:
    mov eax, 42
    ret
```

```text
xirasm hello.asm --target x86-64 -o hello.bin
```

## 一套工具，多种目标

| CLI 目标 | 输出模型 |
| --- | --- |
| `x86-64`、`x64`、`x86_64` | 64 位 x86 指令与原生/flat 输出 |
| `x86`、`x86-32` | 32 位 x86 指令与原生/flat 输出 |
| `rv64`、`riscv64` | RV64 指令 |
| `rv32`、`riscv32` | RV32 指令 |
| `spv`、`spirv` | 完整 SPIR-V 1.6 模块 |

AArch64 指令文本来自生成好的 include 层，而不是 CLI 目标：
`import("arm/a64-macros.inc")` 之后即可汇编 `mov x8, #93` 与 `svc #0`，由格式
接口决定结果是 ELF64 镜像、PE64 镜像、目标文件还是 Mach-O 镜像。

切换目标时，工程模型和编译期语言保持一致。用户不必为 x86 学一套宏系统，再为
RISC-V 或 SPIR-V 学另一套代码生成方式。

## 支持的输出格式

XIRASM 可以直接生成：

| 平台或用途 | 格式 |
| --- | --- |
| Windows | x86 与 ARM64 的 PE32/PE64 可执行文件与 DLL；x86 与 ARM64 的 COFF32/COFF64 目标文件 |
| Linux | ELF32/ELF64 可执行文件；x86-64 与 AArch64 的 ELF64 PIE 与共享库；ELF32/ELF64 目标文件 |
| macOS | x86_64 与 arm64 的 Mach-O 64 可执行文件、dylib 与目标文件，含 dyld 导入、桩与导出表 |
| Android | APK 归档：ZIP 容器、二进制清单、编译后的资源表、assets 与按 ABI 划分的原生库 |
| 裸机与工具开发 | flat binary 与应用专用二进制 |
| GPU 与 IR 工具 | 完整 SPIR-V 1.6 模块 |

常规 PE、COFF 与 ELF 项目使用格式库的高层封装：

```asm
import("format/format.inc");
```

如果自定义加载器、文件格式或研究工具需要特殊布局，同一门语言还提供 region、label、
alignment、finalizer 与直接格式辅助接口。常见任务保持简单，底层控制也没有被藏起来。

## 构建 Android APK

APK 就是一个装着二进制清单与编译后资源表的 ZIP 归档。这三部分 XIRASM 都能写出，
而里面的原生库可以和汇编代码来自同一个工程：

```asm
import("format/apk.inc");

origin(0)

let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
app = apk_res_dir(app, "res")
app = apk_native_lib(app, "arm64-v8a", "libdemo.so", "build/arm64-v8a/libdemo.so")
apk_emit(app)
```

产物可以直接安装运行：没有 DEX、没有 Java 源文件，也不依赖任何第三方运行时，
Activity 就是 NativeActivity，入口是共享库自己导出的 `ANativeActivity_onCreate`。
`tests/format/android_gl_demo/` 是一份完整的 GLES2 渲染器加上包住它的归档，两者
都由汇编器写出，构建出 39 KB 的 APK，并能被 `aapt2` 与 `zipalign` 完整读回。签名
仍然留在汇编器之外，SDK 命令序列见 [Android 指南](document/apk.md)。

## 不只是另一套宏汇编器

当汇编项目开始出现大量复制、替换与生成逻辑时，XIRASM 提供的是一门真正的编译期
语言：

- 类型化常量、可变绑定、函数与词法作用域；
- `if`/`else if`、`while`、`for`、`break` 与 `continue`；
- string、bytes、可变 list 与 map；
- struct、union、pack、alignment 与 reserve；
- module、import、JSON、TOML 与文件驱动生成；
- 用于紧凑领域语法的 token matching；
- assert 与定位到原始源码的诊断。

因此它既适合系统程序和嵌入式二进制，也适合可执行格式、代码生成器与指令级实验；
同时不会把普通 ISA 指令改造成一套编程语言 API。

## 验证

回归测试关注最终编码字节和边界行为，而不只是“源码能够解析”。覆盖内容包括 x86
布局与 fixup、与 LLVM 工具对照的 RISC-V 与 AArch64 字节、SPIR-V 汇编/反汇编与
验证，以及受支持二进制格式的结构检查、链接、加载和真机运行测试。结果还由独立
工具复核：指令编码与 ELF、COFF、Mach-O 结构交给 LLVM 工具，APK 交给 Android SDK
的 `aapt2`、`zipalign` 以及一个独立的解压实现。

## 编辑器与文档

独立的 [XIRASM VS Code 扩展](https://github.com/XIRASM/xir-vscode)
提供语法高亮、补全、导航与编译器诊断。

- [完整中文文档 PDF](document/zh/pdf/xirasm-documentation-zh-CN.pdf) - 合并语言指南、
  格式教程与语言 API 参考，适合离线阅读。
- [中文语言指南](document/zh/language.md) - 学习汇编器与编译期语言模型。
- [中文格式教程](document/zh/format-tutorial.md) - 使用高层封装构建 PE、COFF 与 ELF。
- [Android 指南（英文）](document/apk.md) - 汇编 NativeActivity 库，以及包住它的
  APK、资源表与清单。
- [中文语言 API 参考](document/zh/api-reference.md) - 查询语法与内置 API。
- [高级格式构造指南（英文）](document/advanced-formats.md) - 直接控制特殊二进制布局。

## 状态

当前版本：**0.2.21**。参见[版本说明](document/zh/releases/0.2.21.md)。

XIRASM 仍处于 1.0 之前。汇编器、语言 API、格式库、CLI 与编辑器支持目前已经可以
实际使用，公开契约在 1.0 前仍可能继续收敛。

## 许可证

Apache-2.0。
