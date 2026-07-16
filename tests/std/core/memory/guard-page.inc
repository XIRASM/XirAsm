// std/core memory 的跨平台不可访问页边界测试。
//
// 每块分配两个页，只开放第一页读写并把第二页改为不可访问。所有测试范围
// 紧贴页尾；任何向量越界读取或写入都会让真机进程异常终止。

import("format/format.inc");
import("std/core.inc");
x86.use64();

const guard_is_windows: bool = test_memory_abi == std_core_abi_windows64
const guard_page_size: u64 = 4096
const guard_allocation_size: u64 = 8192

fn guard_exit(status: u64) {
    if guard_is_windows {
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

fn guard_call_runtime(symbol: string) {
    if guard_is_windows {
        sub rsp, 40
    }
    isa(sym.join("call ", symbol));
    if guard_is_windows {
        add rsp, 40
    }
}

// 输入统一使用 R10=参数1、R11=参数2、R8=长度，再映射到目标 ABI。
fn guard_call_binary(symbol: string) {
    if guard_is_windows {
        mov rcx, r10
        mov rdx, r11
    } else {
        mov rdi, r10
        mov rsi, r11
        mov rdx, r8
    }
    guard_call_runtime(symbol);
}

fn guard_allocate(slot_label: string, failed_label: string) {
    if guard_is_windows {
        xor ecx, ecx
        mov edx, guard_allocation_size
        mov r8d, 0x3000
        mov r9d, 4
        sub rsp, 40
        call [rel VirtualAlloc]
        add rsp, 40
        test rax, rax
        isa(sym.join("jz ", failed_label));
        isa(sym.join("mov [rel ", slot_label, "], rax"));

        mov rcx, rax
        add rcx, guard_page_size
        mov edx, guard_page_size
        mov r8d, 1
        lea r9, [rel guard_old_protect]
        sub rsp, 40
        call [rel VirtualProtect]
        add rsp, 40
        test eax, eax
        isa(sym.join("jz ", failed_label));
    } else {
        xor edi, edi
        mov esi, guard_allocation_size
        mov edx, 3
        mov r10d, 0x22
        mov r8, -1
        xor r9d, r9d
        mov eax, 9
        syscall
        test rax, rax
        isa(sym.join("js ", failed_label));
        isa(sym.join("mov [rel ", slot_label, "], rax"));

        mov rdi, rax
        add rdi, guard_page_size
        mov esi, guard_page_size
        xor edx, edx
        mov eax, 10
        syscall
        test rax, rax
        isa(sym.join("jnz ", failed_label));
    }
}

let guard_imports: map = pe_import_new()
if guard_is_windows {
    guard_imports = pe_import_use64_many(
        guard_imports,
        "KERNEL32.DLL",
        list.of("ExitProcess", "VirtualAlloc", "VirtualProtect")
    )
}

let guard_image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
if guard_is_windows {
    guard_image = format_pe64(
        format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
        list.of(
            format_section(".text", format_code | format_readable | format_executable),
            format_section(".data", format_data | format_readable | format_writeable),
            format_section(".idata", format_imports | format_readable | format_writeable)
        )
    )
}
format_begin(guard_image);

if guard_is_windows {
    format_section_begin(guard_image, ".text");
} else {
    format_segment_begin(guard_image, ".text");
}
guard_start:
    guard_allocate("guard_source", "guard_failed_allocate");
    guard_allocate("guard_target", "guard_failed_allocate");

    lea r13, [rel guard_lengths]
    mov r14d, 13
guard_next_length:
    mov r15, [r13]

    // 每轮把两个开放页初始化成不同值，完整页填充本身也紧贴 guard page。
    mov r10, [rel guard_source]
    mov r11, 0x5a
    mov r8, guard_page_size
    guard_call_binary(std_memory_fill_symbol);
    mov r10, [rel guard_target]
    xor r11d, r11d
    mov r8, guard_page_size
    guard_call_binary(std_memory_fill_symbol);

    // copy 的源和目标都恰好结束在不可访问页之前。
    mov r10, [rel guard_target]
    add r10, guard_page_size
    sub r10, r15
    mov r12, r10
    mov r11, [rel guard_source]
    add r11, guard_page_size
    sub r11, r15
    mov r8, r15
    guard_call_binary(std_memory_copy_symbol);
    cmp rax, r12
    jne guard_failed_memory

    mov r10, [rel guard_target]
    add r10, guard_page_size
    sub r10, r15
    mov r8, r15
    test r8, r8
    jz guard_copy_checked
guard_check_copy:
    cmp byte [r10], 0x5a
    jne guard_failed_memory
    add r10, 1
    sub r8, 1
    jnz guard_check_copy
guard_copy_checked:

    // fill 精确覆盖页尾，随后 compare 验证 unsigned 关系和相等路径。
    mov r10, [rel guard_target]
    add r10, guard_page_size
    sub r10, r15
    mov r12, r10
    mov r11, 0xa5
    mov r8, r15
    guard_call_binary(std_memory_fill_symbol);
    cmp rax, r12
    jne guard_failed_memory

    mov r10, [rel guard_target]
    add r10, guard_page_size
    sub r10, r15
    mov r8, r15
    test r8, r8
    jz guard_fill_checked
guard_check_fill:
    cmp byte [r10], 0xa5
    jne guard_failed_memory
    add r10, 1
    sub r8, 1
    jnz guard_check_fill
guard_fill_checked:

    mov r10, [rel guard_source]
    add r10, guard_page_size
    sub r10, r15
    mov r11, [rel guard_target]
    add r11, guard_page_size
    sub r11, r15
    mov r8, r15
    guard_call_binary(std_memory_compare_symbol);
    test r15, r15
    jz guard_compare_zero
    test rax, rax
    jns guard_failed_memory
    jmp guard_compare_ordered
guard_compare_zero:
    test rax, rax
    jne guard_failed_memory
guard_compare_ordered:

    mov r10, [rel guard_target]
    mov r11, 0x5a
    mov r8, guard_page_size
    guard_call_binary(std_memory_fill_symbol);
    mov r10, [rel guard_source]
    add r10, guard_page_size
    sub r10, r15
    mov r11, [rel guard_target]
    add r11, guard_page_size
    sub r11, r15
    mov r8, r15
    guard_call_binary(std_memory_compare_symbol);
    test rax, rax
    jne guard_failed_memory


    // move 的两个方向都让其中一个范围紧贴不可访问页。
    test r15, r15
    jz guard_move_zero
    mov r11, [rel guard_source]
    add r11, guard_page_size
    sub r11, 1
    sub r11, r15
    mov r10, r11
    add r10, 1
    mov r12, r10
    mov r8, r15
    guard_call_binary(std_memory_move_symbol);
    cmp rax, r12
    jne guard_failed_memory

    mov r10, [rel guard_source]
    add r10, guard_page_size
    sub r10, 1
    sub r10, r15
    mov r11, r10
    add r11, 1
    mov r12, r10
    mov r8, r15
    guard_call_binary(std_memory_move_symbol);
    cmp rax, r12
    jne guard_failed_memory
    jmp guard_move_checked
guard_move_zero:
    mov r10, [rel guard_source]
    add r10, guard_page_size
    mov r11, r10
    mov r12, r10
    xor r8d, r8d
    guard_call_binary(std_memory_move_symbol);
    cmp rax, r12
    jne guard_failed_memory
guard_move_checked:

    add r13, 8
    sub r14d, 1
    jnz guard_next_length
    guard_exit(0);
guard_failed_allocate:
    guard_exit(1);
guard_failed_memory:
    guard_exit(2);

std_memory_emit_tier(test_memory_abi, test_memory_tier);

if guard_is_windows {
    format_section_end(guard_image, ".text");
    format_section_begin(guard_image, ".data");
} else {
    format_segment_end(guard_image, ".text");
    format_segment_begin(guard_image, ".data");
}
guard_source:
    dq(0);
guard_target:
    dq(0);
guard_old_protect:
    dd(0);
guard_lengths:
    dq(0, 1, 7, 8, 15, 16, 17, 31, 32, 33, 63, 64, 65);
if guard_is_windows {
    format_section_end(guard_image, ".data");
    format_pe_import_section(guard_image, ".idata", guard_imports);
} else {
    format_segment_end(guard_image, ".data");
}

format_entry_mut(guard_image, guard_start)
format_finish(guard_image);
