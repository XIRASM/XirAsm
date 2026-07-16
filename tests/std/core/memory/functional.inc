// std/core memory 的跨平台功能和 ABI 真机测试体。
//
// 包装文件提供 test_memory_abi 与 test_memory_tier。本文件利用 XIRASM
// 编译期分支生成 PE64 或 ELF64，同时复用同一组运行时测试逻辑。

import("format/format.inc");
import("std/core.inc");
x86.use64();

const test_is_windows: bool = test_memory_abi == std_core_abi_windows64

fn test_exit(status: u64) {
    if test_is_windows {
        sub rsp, 40
        mov ecx, status
        call [rel ExitProcess]
        add rsp, 40
    } else {
        mov eax, 60
        mov edi, status
        syscall
    }
}

fn test_call_runtime(symbol: string) {
    if test_is_windows {
        sub rsp, 40
    }
    isa(sym.join("call ", symbol));
    if test_is_windows {
        add rsp, 40
    }
}

fn test_call_binary(symbol: string, first: string, first_offset: u64, second: string, second_offset: u64, count: u64) {
    if test_is_windows {
        isa(sym.join("lea rcx, [rel ", first, " + ", first_offset, "]"));
        isa(sym.join("lea rdx, [rel ", second, " + ", second_offset, "]"));
        mov r8, count
    } else {
        isa(sym.join("lea rdi, [rel ", first, " + ", first_offset, "]"));
        isa(sym.join("lea rsi, [rel ", second, " + ", second_offset, "]"));
        mov rdx, count
    }
    test_call_runtime(symbol);
}

fn test_call_fill(target: string, target_offset: u64, value: u64, count: u64) {
    if test_is_windows {
        isa(sym.join("lea rcx, [rel ", target, " + ", target_offset, "]"));
        mov rdx, value
        mov r8, count
    } else {
        isa(sym.join("lea rdi, [rel ", target, " + ", target_offset, "]"));
        mov rsi, value
        mov rdx, count
    }
    test_call_runtime(std_memory_fill_symbol);
}

fn test_call_zero_copy() {
    if test_is_windows {
        mov ecx, 1
        mov edx, 2
        xor r8d, r8d
    } else {
        mov edi, 1
        mov esi, 2
        xor edx, edx
    }
    test_call_runtime(std_memory_copy_symbol);
}

fn test_call_zero_compare() {
    if test_is_windows {
        mov ecx, 1
        mov edx, 2
        xor r8d, r8d
    } else {
        mov edi, 1
        mov esi, 2
        xor edx, edx
    }
    test_call_runtime(std_memory_compare_symbol);
}

fn test_check_bytes(left: string, left_offset: u64, right: string, right_offset: u64, count: u64, failed_label: string) {
    const loop: string = sym.unique("__std_mem_test_bytes_loop_")
    const done: string = sym.unique("__std_mem_test_bytes_done_")

    isa(sym.join("lea r10, [rel ", left, " + ", left_offset, "]"));
    isa(sym.join("lea r11, [rel ", right, " + ", right_offset, "]"));
    mov r8, count
    test r8, r8
    isa(sym.join("jz ", done));
    label.define(loop);
    movzx eax, byte [r10]
    cmp al, byte [r11]
    isa(sym.join("jne ", failed_label));
    add r10, 1
    add r11, 1
    sub r8, 1
    isa(sym.join("jnz ", loop));
    label.define(done);
}

fn test_seed_nonvolatile() {
    mov ebx, 0x11111111
    mov ebp, 0x22222222
    mov r12d, 0x33333333
    mov r13d, 0x44444444
    mov r14d, 0x55555555
    mov r15d, 0x66666666
    if test_is_windows {
        mov edi, 0x77777777
        mov esi, 0x12345678
        movdqu xmm6, [rel xmm6_seed]
    }
}

fn test_check_nonvolatile(failed_label: string) {
    cmp rbx, 0x11111111
    isa(sym.join("jne ", failed_label));
    cmp rbp, 0x22222222
    isa(sym.join("jne ", failed_label));
    cmp r12, 0x33333333
    isa(sym.join("jne ", failed_label));
    cmp r13, 0x44444444
    isa(sym.join("jne ", failed_label));
    cmp r14, 0x55555555
    isa(sym.join("jne ", failed_label));
    cmp r15, 0x66666666
    isa(sym.join("jne ", failed_label));
    cmp rsp, [rel saved_rsp]
    isa(sym.join("jne ", failed_label));
    pushfq
    pop rax
    test eax, 0x400
    isa(sym.join("jnz ", failed_label));
    if test_is_windows {
        cmp rdi, 0x77777777
        isa(sym.join("jne ", failed_label));
        cmp rsi, 0x12345678
        isa(sym.join("jne ", failed_label));
        movdqu [rel xmm6_after], xmm6
        mov rax, [rel xmm6_after]
        cmp rax, [rel xmm6_seed]
        isa(sym.join("jne ", failed_label));
        mov rax, [rel xmm6_after + 8]
        cmp rax, [rel xmm6_seed + 8]
        isa(sym.join("jne ", failed_label));
    }
}

let imports: map = pe_import_new()
if test_is_windows {
    imports = pe_import_use64(imports, "KERNEL32.DLL", "ExitProcess")
}

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
if test_is_windows {
    image = format_pe64(
        format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
        list.of(
            format_section(".text", format_code | format_readable | format_executable),
            format_section(".rdata", format_data | format_readable),
            format_section(".data", format_data | format_readable | format_writeable),
            format_section(".idata", format_imports | format_readable | format_writeable)
        )
    )
}
format_begin(image);

if test_is_windows {
    format_section_begin(image, ".text");
} else {
    format_segment_begin(image, ".text");
}
start:
    mov [rel saved_rsp], rsp
    test_seed_nonvolatile();

    // copy：零长度不得访问哨兵指针；33 字节覆盖 16 字节边界和未对齐地址。
    test_call_zero_copy();
    cmp rax, 1
    jne failed_copy
    test_call_binary(std_memory_copy_symbol, "copy_buffer", 5, "source_data", 3, 33);
    lea rcx, [rel copy_buffer + 5]
    cmp rax, rcx
    jne failed_copy
    test_check_bytes("copy_buffer", 5, "source_data", 3, 33, "failed_copy");

    // fill：value 只取低 8 位，并精确写入 33 字节。
    test_call_fill("fill_buffer", 7, 0x1234a5, 33);
    lea rcx, [rel fill_buffer + 7]
    cmp rax, rcx
    jne failed_fill
    test_check_bytes("fill_buffer", 7, "fill_expected", 0, 33, "failed_fill");
    cmp byte [rel fill_buffer + 6], 0
    jne failed_fill
    cmp byte [rel fill_buffer + 40], 0
    jne failed_fill

    // move：目标在源后、目标在源前、同地址三类重叠。
    test_call_binary(std_memory_copy_symbol, "move_buffer", 0, "source_data", 0, 64);
    test_call_binary(std_memory_move_symbol, "move_buffer", 5, "move_buffer", 0, 33);
    lea rcx, [rel move_buffer + 5]
    cmp rax, rcx
    jne failed_move
    test_check_bytes("move_buffer", 0, "source_data", 0, 5, "failed_move");
    test_check_bytes("move_buffer", 5, "source_data", 0, 33, "failed_move");
    test_check_bytes("move_buffer", 38, "source_data", 38, 26, "failed_move");

    test_call_binary(std_memory_copy_symbol, "move_buffer", 0, "source_data", 0, 64);
    test_call_binary(std_memory_move_symbol, "move_buffer", 0, "move_buffer", 5, 33);
    test_check_bytes("move_buffer", 0, "source_data", 5, 33, "failed_move");
    test_check_bytes("move_buffer", 33, "source_data", 33, 31, "failed_move");

    test_call_binary(std_memory_move_symbol, "move_buffer", 0, "move_buffer", 0, 64);
    lea rcx, [rel move_buffer]
    cmp rax, rcx
    jne failed_move
    test_check_bytes("move_buffer", 0, "source_data", 5, 33, "failed_move");

    // compare：向量边界前后和高位字节均按 unsigned 首差异比较。
    test_call_binary(std_memory_copy_symbol, "compare_left", 0, "source_data", 0, 64);
    test_call_binary(std_memory_copy_symbol, "compare_right", 0, "source_data", 0, 64);
    test_call_binary(std_memory_compare_symbol, "compare_left", 0, "compare_right", 0, 33);
    test rax, rax
    jne failed_compare

    mov byte [rel compare_right], 0xff
    test_call_binary(std_memory_compare_symbol, "compare_left", 0, "compare_right", 0, 33);
    test rax, rax
    jns failed_compare
    mov byte [rel compare_right], 0

    mov byte [rel compare_right + 15], 0
    test_call_binary(std_memory_compare_symbol, "compare_left", 0, "compare_right", 0, 33);
    cmp rax, 0
    jle failed_compare
    mov byte [rel compare_right + 15], 15

    mov byte [rel compare_right + 16], 0xff
    test_call_binary(std_memory_compare_symbol, "compare_left", 0, "compare_right", 0, 33);
    test rax, rax
    jns failed_compare
    mov byte [rel compare_right + 16], 16

    mov byte [rel compare_right + 32], 0
    test_call_binary(std_memory_compare_symbol, "compare_left", 0, "compare_right", 0, 33);
    cmp rax, 0
    jle failed_compare

    mov byte [rel compare_left + 16], 0x80
    mov byte [rel compare_right + 16], 0x7f
    test_call_binary(std_memory_compare_symbol, "compare_left", 0, "compare_right", 0, 33);
    cmp rax, 0
    jle failed_compare

    test_call_zero_compare();
    test rax, rax
    jne failed_compare

    test_check_nonvolatile("failed_abi");
    test_exit(0);
failed_copy:
    test_exit(1);
failed_fill:
    test_exit(2);
failed_move:
    test_exit(3);
failed_compare:
    test_exit(4);
failed_abi:
    test_exit(5);

std_memory_emit_tier(test_memory_abi, test_memory_tier);

if test_is_windows {
    format_section_end(image, ".text");
    format_section_begin(image, ".rdata");
} else {
    format_segment_end(image, ".text");
    format_segment_begin(image, ".rodata");
}
source_data:
for value in range(0, 64) {
    db(value);
}
fill_expected:
for value in range(0, 33) {
    db(0xa5);
}
xmm6_seed:
    dq(0x0123456789abcdef, 0xfedcba9876543210);
if test_is_windows {
    format_section_end(image, ".rdata");
    format_section_begin(image, ".data");
} else {
    format_segment_end(image, ".rodata");
    format_segment_begin(image, ".data");
}
saved_rsp:
    dq(0);
xmm6_after:
    dq(0, 0);
copy_buffer:
for slot in range(0, 10) {
    dq(0);
}
fill_buffer:
for slot in range(0, 10) {
    dq(0);
}
move_buffer:
for slot in range(0, 10) {
    dq(0);
}
compare_left:
for slot in range(0, 10) {
    dq(0);
}
compare_right:
for slot in range(0, 10) {
    dq(0);
}
if test_is_windows {
    format_section_end(image, ".data");
    format_pe_import_section(image, ".idata", imports);
} else {
    format_segment_end(image, ".data");
}

format_entry_mut(image, start)
format_finish(image);
