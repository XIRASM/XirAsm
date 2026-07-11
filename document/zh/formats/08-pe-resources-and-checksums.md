# 第 8 章：PE 资源与校验和

资源和校验和都是 PE 文件映像中的可选内容，但用途完全不同：

- 资源把结构化的应用程序数据附加到文件映像中；
- PE 校验和记录最终物理文件的校验结果。

这两类内容都不属于代码节。常用格式接口会为资源安排专用节，并且只在文件映像中的字节已经稳定后计算校验和。

## 资源使用专用节

使用 `format_resources` 用途声明一个可读资源节：

```text
format_section(".rsrc", format_resources | format_readable)
```

资源数据通常由操作系统或应用程序代码读取，不需要写入或执行权限。

常用辅助接口负责资源节的完整构建流程：

```text
format_pe_resource_section(image, ".rsrc", "app.res")
```

这项调用会完成以下操作：

1. 打开已经声明的资源节；
2. 根据最终 PE 布局推导该节的相对虚拟地址；
3. 解析已经编译的资源记录；
4. 构造资源类型、名称和语言目录树；
5. 写入资源数据项及其实际内容；
6. 关闭资源节；
7. 登记 PE 资源数据目录中的字段。

不要在这项调用外部手工打开 `.rsrc`。普通源代码只需提供节名称和已编译资源文件的路径，不需要提供资源的相对虚拟地址或目录偏移。

## 使用已编译的资源文件

`format_pe_resource_section` 接受已经编译的 `.res` 文件，不接受 `.rc` 资源脚本，也不会把整个 `.res` 文件当作一段不透明数据直接嵌入。

资源编译器会先把供人编写的资源脚本及其输入文件转换成已编译的资源记录。XIRASM 随后读取这些记录，并重新构造 PE 资源层次结构。

一个已编译资源文件可以包含：

- 使用数字或名称表示的资源类型；
- 使用数字或名称表示的资源标识；
- 多个数字语言标识；
- 共享同一类型或名称的多个资源内容。

格式接口会按确定的顺序排列目录项，保留每份资源内容的准确大小，并应用 PE 资源格式要求的对齐。内容为空的已编译记录不会生成资源叶项。

相对路径遵循其他文件接口使用的源文件相对路径解析规则。因此，源文件与 `app.res` 位于同一目录时，可以直接写：

```text
format_pe_resource_section(image, ".rsrc", "app.res")
```

一个文件映像使用的全部资源应合并到同一份已编译资源文件中，再由唯一一个声明为 `format_resources` 的节读取。

## 带有资源和校验和的 PE64 可执行文件

下面的示例为一个小型 PE64 可执行文件加入已编译资源文件，并在文件映像完成后计算校验和：

```asm
// 导入 PE、COFF 和 ELF 的常用格式构造接口。
import("format/format.inc");

// 声明固定基址的 PE64 控制台程序，并为代码和资源分别安排节。
const image0: map = format_pe64(
    format_pe_exe |
    format_pe_console |
    format_pe_nx |
    format_pe_aslr_disabled,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".rsrc",
            format_resources | format_readable
        )
    )
)

// 开始按照已经声明的节顺序构造文件映像。
format_begin(image0);

// 在代码节中写入返回零的程序入口。
format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

// 解析同目录中的已编译资源文件，并生成完整的资源节。
format_pe_resource_section(
    image0,
    ".rsrc",
    "app.res"
);

// 绑定入口并完成布局，然后对最终物理文件计算 PE 校验和。
const image: map = format_entry(image0, start)
format_finish(image);
format_pe_checksum(image);
```

格式方案确定 `.rsrc` 是第二个节。源代码不需要计算它的节表项索引、原始数据文件位置、相对虚拟地址、目录偏移或最终大小。

校验和调用也不需要接收节列表。它会读取已经声明的 PE 格式方案，并按照声明顺序处理文件头和每个节在文件中的实际字节。

## 校验和覆盖最终文件

`format_pe_checksum(image)` 会把校验和计算登记为最终操作。它会：

1. 读取 PE 文件头时把校验和字段按零处理；
2. 累加每个已声明节在文件中的实际字节；
3. 归并累计得到的 16 位和；
4. 加上最终物理文件大小；
5. 把结果保存到可选文件头中。

只存在于内存的未初始化数据区不提供任何文件字节。它的逻辑大小仍会影响加载后的内存映像，但不会为校验和增加需要读取的数据。

PE 校验和不是数字签名，也不能证明文件内容未被恶意修改。它只是 PE 格式规定的一个校验字段。签名、信任关系和防篡改能力属于另外的问题。

## 在校验和之前登记字节回填

各项收尾处理按照登记顺序执行。任何会改变输出字节的收尾处理，都必须在 `format_pe_checksum` 之前登记。

例如，绝对指针的回填应放在校验和之前：

```text
format_finish(image)

defer {
    store.u64(pointer_slot, target);
}

format_pe_checksum(image)
```

这样，校验和读取到的就是已经写入的指针值。只读取数据的断言可以登记在校验和之后，因为它不会改变文件内容。

计算校验和后，不要再修改、追加、签名或以其他方式重写文件；如果后续操作确实会改写文件，就必须按照该操作自身的文件处理规则同时更新校验和。

## 可执行文件和动态链接库都能使用资源

同一个资源辅助接口既适用于 PE32 和 PE64 格式方案，也适用于可执行文件和动态链接库。已编译资源的表示方式不依赖指针位宽。

校验和辅助接口同样不要求用户为不同位宽采用不同流程。PE32 和 PE64 的校验和字段位于可选文件头中相同的相对位置，格式接口会自动使用正确的文件映像布局。

资源与导入、导出和基址重定位彼此独立。较大的文件映像可以同时声明以下自动生成内容所使用的节：

```text
list.of(
    format_section(
        ".text",
        format_code | format_readable | format_executable
    ),
    format_section(
        ".idata",
        format_imports | format_readable | format_writeable
    ),
    format_section(
        ".edata",
        format_exports | format_readable
    ),
    format_section(
        ".rsrc",
        format_resources | format_readable
    ),
    format_section(
        ".reloc",
        format_fixups | format_readable | format_discardable
    )
)
```

每个自动生成辅助接口都负责对应节的完整构建流程。这些节完成构建，并登记完所有会改变字节的回填后，再登记校验和计算。

## 资源和校验和的常见错误

### 传入 `.rc` 资源脚本

资源辅助接口读取已经编译的 `.res` 记录。应先编译资源脚本，再汇编 PE 文件映像。

### 把 `.res` 文件当作普通原始数据

辅助接口会解析其中的记录并重新构造 PE 资源树。如果需要的结果只是一段不透明的字节序列，应使用普通的数据写出功能。

### 声明错误的节用途

`format_pe_resource_section` 要求目标节使用 `format_resources` 用途声明。

### 手工打开 `.rsrc`

常用资源辅助接口会自行打开资源节、写出内容、完成相关字段并关闭该节。不要在调用外部再添加一组开始和结束操作。

### 过早计算校验和

应先登记所有会改变字节的 `defer` 块。校验和如果根据占位字节计算，后续收尾处理写入真实值后就会失效。

### 把校验和当作身份验证

校验和本身无法发现恶意替换。需要确认文件来源和真实性时，应使用合适的签名与验证机制。

## 资源和校验和的实用规则

1. 把一个文件映像使用的资源脚本编译成一份 `.res` 输入文件。
2. 声明一个可读的 `format_resources` 节。
3. 让 `format_pe_resource_section` 负责 `.rsrc` 的完整构建流程。
4. 传入文件路径、名称和标号，不要传入资源相对虚拟地址或表项索引。
5. 在计算校验和之前完成导入、导出、资源和重定位内容。
6. 在 `format_pe_checksum` 之前登记每一项最终字节回填。
7. 把未初始化数据区视为内存大小，而不是文件字节。
8. 仅在输出流程确实需要时计算校验和。
9. 不要混淆 PE 校验和与数字签名。
10. 后续操作只要改变了校验和覆盖的字节，就应重新计算校验和。

第 9 章将从可以加载的 PE 文件映像转向 COFF 目标文件。在目标文件中，节、符号和重定位描述的是本机链接器需要完成的工作，而不是加载器需要完成的工作。

[返回可执行文件格式指南](../formats.md)
