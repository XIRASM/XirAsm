# 第 6 章：导入 Windows 接口函数

PE 可执行文件不会包含它调用的每个函数的实现。导入表记录程序需要使用的动态链接库和函数，Windows 加载器解析这些函数后，会把它们的地址写入文件映像中的导入地址表。

常用格式接口允许源代码按名称声明导入项。它会生成描述项、查找表、提示值与名称记录、动态链接库名称、地址表槽位、结束项，以及 PE 导入目录项。

## 导入集合是不可变的编译期值

先创建一个空的导入集合：

```text
const imports0: map = pe_import_new()
```

每次加入所需函数时，都会返回一个新的映射：

```text
const imports1: map = pe_import_use64(
    imports0,
    "KERNEL32.DLL",
    "ExitProcess"
)
```

应根据文件映像的位数选择对应函数：

| 文件映像 | 按名称导入 | 按名称导入并指定本地槽位名称 |
| --- | --- | --- |
| PE32 | `pe_import_use32` | `pe_import_use32_as` |
| PE64 | `pe_import_use64` | `pe_import_use64_as` |

不带 `_as` 的形式会直接使用被导入函数的名称作为本地导入地址表标号。带 `_as` 的形式则把外部函数名称与汇编源代码使用的标号分开：

```text
pe_import_use64_as(
    imports,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)
```

这段声明记录了三项信息：

```text
动态链接库名称        KERNEL32.DLL
导入的函数            ExitProcess
本地地址表标号        exit_process
```

该标号表示导入地址表中的一个槽位，而不是函数实现本身。文件映像加载完成后，这个槽位中保存的是已经解析出的函数地址。

## 在映像方案中声明导入节

格式方案必须包含一个用途为 `format_imports` 的节：

```text
format_section(
    ".idata",
    format_imports | format_readable | format_writeable
)
```

加载器需要填写其中的地址表槽位，因此该节必须可写。它不需要执行权限。

使用下面的函数写出完整导入集合：

```text
format_pe_import_section(image, ".idata", imports)
```

这个操作会自行打开并关闭指定的节。不要再在它外面调用一组单独的 `format_section_begin` 和 `format_section_end`。

## 调用导入函数的 PE64 可执行文件

下面的可执行文件导入 `ExitProcess`，为其导入地址表槽位指定小写的本地名称，并通过相对于下一条指令寻址的内存操作数调用它：

```asm
// 导入常用格式接口，选择 64 位 x86 指令模式。
import("format/format.inc");
x86.use64();

// 声明 ExitProcess 导入项，并为地址表槽位指定本地标号。
const imports0: map = pe_import_new()
const imports: map = pe_import_use64_as(
    imports0,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)

// 创建包含代码节和可写导入节的 PE64 控制台映像。
const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".idata",
            format_imports | format_readable | format_writeable
        )
    )
)
format_begin(image0);

// 按 Windows 64 位调用约定传入零，并通过导入地址表间接调用函数。
format_section_begin(image0, ".text");
start:
    sub rsp, 40
    xor ecx, ecx
    call [rel exit_process]
format_section_end(image0, ".text");

// 根据完整导入集合生成 .idata 节。
format_pe_import_section(image0, ".idata", imports);

// 绑定入口标号并完成文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

将它汇编为 64 位 Windows 可执行文件并运行：

```powershell
# 生成 PE64 文件，然后运行该程序。
xirasm imported-exit.asm --target x86-64 -o imported-exit.exe
.\imported-exit.exe
```

程序把零传给 `ExitProcess`，并以退出状态 0 结束。

## 遵循 Windows 64 位调用约定

前四个整数或指针参数依次使用：

```text
参数 0    rcx
参数 1    rdx
参数 2    r8
参数 3    r9
```

调用者还必须预留 32 字节的影子空间，并在调用边界保持栈地址按 16 字节对齐。上面的示例使用：

```text
sub rsp, 40
xor ecx, ecx
call [rel exit_process]
```

在通常的函数入口处，40 字节的调整量同时包含 32 字节影子空间和保持对齐所需的额外空间。`ExitProcess` 不会返回。调用会返回的导入函数时，应在离开当前过程前恢复栈指针：

```text
sub rsp, 40
设置参数寄存器
call [rel imported_slot]
add rsp, 40
```

按照 Windows 64 位调用约定，易失寄存器在调用后应视为已经改变。使用非易失寄存器的代码必须保存并恢复它们。

`rel` 操作数很重要。它让指令相对于下一条指令编码导入地址表槽位的位置，而不是把文件映像的绝对基址写入调用指令。

## PE32 中的导入调用

PE32 使用 32 位导入地址表槽位，并把这个函数的参数压入栈中：

```asm
// 导入常用格式接口，选择 32 位 x86 指令模式。
import("format/format.inc");
x86.use32();

// 声明 ExitProcess 导入项，并为地址表槽位指定本地标号。
const imports0: map = pe_import_new()
const imports: map = pe_import_use32_as(
    imports0,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)

// 创建关闭地址空间布局随机化的 PE32 控制台映像。
const image0: map = format_pe32(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_disabled,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".idata",
            format_imports | format_readable | format_writeable
        )
    )
)
format_begin(image0);

// 将参数零压栈，并通过导入地址表槽位间接调用函数。
format_section_begin(image0, ".text");
start:
    push 0
    call [exit_process]
format_section_end(image0, ".text");

// 生成导入节，绑定入口并完成文件映像。
format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);
```

这个 32 位间接内存操作数包含导入地址表槽位的绝对地址，因此该最小示例选择 `format_pe_aslr_disabled`。第 7 章将说明 PE32 中的绝对地址字段如何参与基址重定位。

不要把 Windows 64 位调用使用的寄存器和影子空间规则套用到 PE32 调用。具体采用哪一种 32 位调用约定、由谁清理参数栈，都由被导入函数的接口约定决定。本例使用 `ExitProcess` 文档规定的栈参数形式。

## 加载器会替换导入地址表内容

文件映像加载之前，每个地址表槽位保存的是导入元数据。导入目录告诉加载器该槽位对应哪个动态链接库和函数。

Windows 加载文件映像时会：

1. 加载或找到每个按名称指定的动态链接库；
2. 解析每个被导入的函数；
3. 把解析出的地址写入对应的导入地址表槽位；
4. 把控制权交给可执行文件入口。

调用指令从槽位中读取已经解析出的地址：

```text
源代码标号          exit_process
标号位置            .idata 中的一个导入地址表槽位
加载后的槽位值      ExitProcess 的地址
调用目标            加载后的槽位值
```

源代码不需要计算导入描述项的相对虚拟地址、查找表的相对虚拟地址、地址表的相对虚拟地址，也不需要计算提示值与名称记录的偏移。

## 添加多个导入项

逐步构造导入集合，并始终保留最近一次返回的映射：

```text
const imports0: map = pe_import_new()
const imports1: map = pe_import_use64_as(
    imports0,
    "KERNEL32.DLL",
    "GetStdHandle",
    "get_std_handle"
)
const imports2: map = pe_import_use64_as(
    imports1,
    "KERNEL32.DLL",
    "WriteFile",
    "write_file"
)
const imports: map = pe_import_use64_as(
    imports2,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)
```

来自同一个动态链接库的导入项共用一个描述项。来自另一个动态链接库的导入项会使用导入映射中的另一个键，并获得另一个描述项。

以同一个动态链接库、导入函数名称和本地槽位名称重复添加同一项不会改变结果。把同一个槽位名称用于不同的导入项则会被拒绝。

常用格式接口会根据最终导入值生成确定的数据表顺序。调用代码应依赖槽位标号，而不应依赖数据表中的位置。

## 按名称导入与按序号导入

通常应按名称导入，因为这种写法能让源代码和诊断信息清楚显示所用函数。格式层也提供按映像位数区分的序号导入形式：

```text
pe_import_use32_ordinal_as(imports, dll, ordinal, slot)
pe_import_use64_ordinal_as(imports, dll, ordinal, slot)
```

导入序号必须能用 16 位表示。只有当目标动态链接库的二进制接口明确把某个序号规定为稳定约定时，才应按序号导入。调用位置仍然使用本地槽位标号。

## 不要把导入元数据放进代码节

导入节包含加载器需要修改的元数据，因此应当可写且不可执行。代码节只应保存指令和普通的指令地址回填项，不应手工放置导入描述项或导入表项数组。

清晰的格式方案会把各项职责分开：

```text
.text     读取 + 执行     调用位置
.rdata    读取            接口函数调用使用的常量
.data     读取 + 写入     可变参数和结果
.idata    读取 + 写入     自动生成的导入元数据和地址表槽位
```

其他数据节并非必需。只声明程序实际使用的节。

## 常见导入错误

### 忘记声明导入节

`format_pe_import_section` 要求格式方案中已经声明一个用途为 `format_imports` 的节。

### 手工打开 `.idata`

常用辅助接口会管理导入节的完整构建流程。手工打开同一个节会造成重复或不匹配的节操作。

### 丢弃更新后的导入映射

每次调用 `pe_import_use*` 都会返回新的映射。如果把较早的映射传给 `format_pe_import_section`，后续添加的导入项不会写入文件映像。

### 调用槽位地址而不是槽位内容

导入标号表示一个指针槽位。应使用 `call [rel exit_process]` 或 `call [exit_process]` 这类间接内存调用，不能直接调用槽位本身的地址。

### 混用位数

PE32 应使用 32 位导入声明，PE64 应使用 64 位导入声明。两者的地址表项宽度和序号标志不同。

### 忽略应用二进制接口

生成正确的导入表并不会自动安排函数参数或栈状态。每个调用位置都必须遵守被导入函数所在平台的应用二进制接口。

## 实用导入规则

1. 为整个文件映像创建一份不可变的导入集合。
2. PE32 使用 `pe_import_use32*`，PE64 使用 `pe_import_use64*`。
3. 本地槽位别名最好与源代码的命名风格一致。
4. 声明一个可写、不可执行且用途为 `format_imports` 的节。
5. 由 `format_pe_import_section` 写出并完成整个 `.idata` 节。
6. 使用间接内存操作数，通过生成的导入地址表标号调用函数。
7. 每个调用位置都遵循正确的 Windows 调用约定。
8. 每次声明导入项后，都保留最新返回的导入映射。
9. 依赖标号和名称，不要依赖自动生成的数据表偏移。
10. 明确处理地址空间布局随机化与绝对地址重定位的要求。

第 7 章会把文件映像从可执行程序改为动态链接库，导出可供调用的符号，并添加绝对地址字段在重定位基址时需要使用的基址重定位信息。

[返回可执行文件格式指南](../formats.md)
