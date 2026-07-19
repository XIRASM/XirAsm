# 5. 通用规则和常见错误

格式文件出错时，先检查配置、名称、权限和调用顺序，再去怀疑 PE/ELF 细节。`format.inc` 会处理大部分头部和表项，错误通常来自声明不一致或调用顺序不对。

## 只使用一层接口

通常只导入：

```asm
import("format/format.inc");
```

不要在同一个输出文件里一边使用 `format_begin`、`format_section_begin`、`format_finish`，一边手写 PE/ELF 头部或表项。需要完整控制格式字段时，就整份文件改用高级格式构造；不要让两套写法同时负责同一张表。

## 可变配置必须是 `let`

格式配置和导入、导出、重定位等集合通常写成 `let`。名称以 `_mut` 结尾的函数会直接更新这个绑定：

```text
let image: map = format_elf64(format_elf_exec, segments)
let imports: list = format_elfexe_import_new()

format_elfexe_import_many_mut(imports, "libc.so.6", list.of("getpid"))
format_elfexe_tables_mut(image, imports)
format_entry_mut(image, start)
```

`_mut` 的可变参数必须是直接的 `let` 名称。下面这些都不适合：

```text
const image: map = format_pe64(options, sections)
format_entry_mut(image, start)

format_entry_mut(format_pe64(options, sections), start)

format_entry_mut(map.get(holder, "image"), start)
```

构造函数仍然可以返回值，例如 `format_section(...)`、`format_segment(...)`、`format_coff_public(...)`。区别在于：描述值可以放进 `const`，后续要被 `_mut` 函数更新的配置或集合要用 `let`。

## 先声明，再写内容

传给 `format_section_begin`、`format_section_end`、`format_segment_begin`、`format_segment_end` 的名称，必须已经出现在配置里：

```text
format_section(".text", format_code | format_readable | format_executable)
```

节名和装载段名必须唯一。PE 和 COFF 节名最多 8 字节。PE 的导入、导出、资源、重定位这类特殊用途节在同一配置里各只能出现一次。

## 每个描述只选一个用途

正确写法：

```text
format_section(".text", format_code | format_readable | format_executable)
```

错误写法：

```text
format_section(".mixed", format_code | format_data | format_readable)
```

一个节只能是代码、数据、BSS、导入、导出、资源或重定位中的一种。一个 ELF 装载段目前只使用 `format_load` 这种用途。

## 权限按运行时需求设置

| 内容 | 常见权限 |
| --- | --- |
| 指令 | 可读、可执行 |
| 常量和字符串 | 可读 |
| 可修改数据 | 可读、可写 |
| BSS | 可读、可写 |
| PE 导入表 | 可读，通常也可写 |
| PE 重定位表 | 可读，通常可丢弃 |

不要把普通数据标记成可执行，也不要让代码可写，除非你确实在构造自修改代码或特殊加载器场景。

## BSS 是内存大小，不是初始化文件内容

`format_uninitialized_data` 表示运行时需要的零初始化内存。里面应使用 `rb(...)` 或 `reserve(...)` 之类预留操作，而不是写入真实初始化字节。`format.inc` 会把内存大小记录进格式表，同时保持对应文件内容为空或不占初始化数据。

## 重定位不是指针本身

写入指针值和声明重定位是两件事：

```text
absolute_slot:
    dq(0);

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, absolute_slot)
format_pe_reloc_section(image, ".reloc", relocs);

defer {
    store.u64(absolute_slot, start);
}
```

`store.u64` 写的是文件里的最终字节；重定位记录告诉加载器或链接器这些字节将来可能需要调整。`format_pe_reloc_add_mut` 的地址参数是存放绝对地址的槽，不是目标标签本身。

## 入口只属于可执行输出

PE 可执行文件、PE DLL、ELF 可执行文件需要 `format_entry_mut(plan, label)`。COFF 目标文件、ELF 目标文件和 ELF 共享库不走这个入口流程。

如果忘记设置入口，`format_finish` 会在 PE 或 ELF 可执行文件上报错；如果给目标文件设置入口，也会报错。

## 导入导出表要在 `format_begin` 前挂到配置上

需要把表项元数据挂到配置上的函数，例如 `format_elfexe_tables_mut`、`format_elfso_tables_mut`、`format_coff_tables_mut`、`format_elfobj_tables_mut`，应在 `format_begin` 前调用。这样 `format.inc` 才能在开始输出时预留正确的头部、程序头、节表或动态表空间。

PE 的 `format_pe_import_section`、`format_pe_export_section`、`format_pe_resource_section`、`format_pe_reloc_section` 是实际生成节内容的函数，应在 `format_begin` 之后、`format_finish` 之前调用，并且不要手动包一层同名 `format_section_begin`。

## `defer` 只做最终回填

`defer` 适合最终检查、地址回填、指针槽写入和校验和这类不改变布局的操作。不要在 `defer` 里新增节、装载段、表项或任意会改变文件大小的内容。参与布局的字节必须在 `format_finish` 前正常写出。

## 从最小模板逐步增加功能

推荐顺序：

1. 先做只有 `.text` 的最小可执行文件；
2. 再加入 `.data` 或 `.bss`；
3. 需要系统函数时加入导入表；
4. 构造 DLL 或共享库时加入导出表；
5. 文件里保存绝对地址时加入基址重定位；
6. 需要交给外部链接器时，改用 COFF 或 ELF 目标文件模板。

这样可以把错误定位在刚新增的格式特性上，而不是一次性排查整份复杂文件。
