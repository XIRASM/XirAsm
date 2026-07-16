# 5. 通用规则和常见错误

## 只使用一层接口

普通程序统一导入：

```asm
import("format/format.inc");
```

不要同时使用普通格式配置和手写底层表项。需要完全控制格式时，改用高级格式构造指南中的 direct 层。

## 配置必须使用 `let`

构造函数返回配置；`_mut` 过程直接修改配置或集合：

```text
let image: map = format_elf64(format_elf_exec, segments)
let imports: list = format_elfexe_import_new()
format_elfexe_import_many_mut(imports, "libc.so.6", list.of("getpid"))
format_elfexe_tables_mut(image, imports)
format_entry_mut(image, start)
```

传给 `_mut` 的目标必须是直接 `let` 绑定，不能是 `const` 或临时表达式。

## 先声明，再写内容

传给 `format_section_begin`、`format_section_end`、`format_segment_begin` 和 `format_segment_end` 的名字必须已经在配置中声明。节名和段名不能重复。

## 每个描述只选一个用途

```text
format_section(".text", format_code | format_readable | format_executable)
```

`format_code` 和 `format_data` 不能同时用于同一个节。用途只选一个，权限可以组合。

## 权限按运行需求设置

| 内容 | 常用权限 |
| --- | --- |
| 指令 | 可读、可执行 |
| 常量和字符串 | 可读 |
| 可修改数据 | 可读、可写 |
| BSS | 可读、可写 |
| PE 导入表 | 可读、可写 |
| PE 重定位表 | 可读、可丢弃 |

除非确实需要自修改代码，否则不要让代码可写；数据也不应具有执行权限。

## BSS 不写入初始化文件内容

在 `format_uninitialized_data` 中使用 `rb(...)` 或 `reserve(...)`。它们增加内存大小，但不会把同样数量的零字节写进文件。

## 重定位和地址值是两件事

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

`store.u64` 写入地址值；重定位记录告诉加载器这个位置需要随镜像基址调整。

## 入口只属于可执行文件

PE 和 ELF 可执行文件使用 `format_entry_mut(plan, label)`。COFF、ELF 目标文件和 ELF 共享库不使用这条入口流程。

## `defer` 只做最终回填

`defer` 可以检查最终字节、回填地址和写校验和，但不能生成会改变布局的新内容。需要参与布局的字节必须在 `format_finish` 前写入正常节或段。

## 从最小模板逐步增加功能

1. 先完成只有 `.text` 的文件。
2. 再加入 `.data` 或 `.bss`。
3. 需要系统函数时加入导入。
4. 构建 DLL 或共享库时加入导出。
5. 文件保存绝对地址时加入基址重定位。
6. 需要链接器继续处理时选择 COFF 或 ELF 目标文件模板。
