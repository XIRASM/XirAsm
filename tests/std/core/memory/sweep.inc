// std/core memory 的密集运行时正确性矩阵。
//
// copy/fill 扫描长度 0..256 和偏移 0..31；move 扫描长度 0..128 与
// 目标相对源 -32..32 的全部距离。reference_buffer 使用独立逐字节算法，
// 每个用例之后比较完整 512 字节，包含目标范围外的 guard 数据。

import("format/format.inc");
import("std/core.inc");
x86.use64();

const sweep_is_windows: bool = test_memory_abi == std_core_abi_windows64
const sweep_is_avx2: bool = test_memory_tier == std_core_memory_tier_avx2
const sweep_is_runtime: bool = test_memory_tier == std_core_dispatch_runtime
const sweep_buffer_size: u64 = 512
const sweep_alignment_count: u64 = 32

fn sweep_exit(status: u64) {
    if sweep_is_windows {
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

fn sweep_call_runtime(symbol: string) {
    if sweep_is_windows {
        sub rsp, 40
    }
    isa(sym.join("call ", symbol));
    if sweep_is_windows {
        add rsp, 40
    }
}

// 输入：R10=参数1，R11=参数2，R8=长度。
fn sweep_call_binary(symbol: string) {
    if sweep_is_windows {
        mov rcx, r10
        mov rdx, r11
    } else {
        mov rdi, r10
        mov rsi, r11
        mov rdx, r8
    }
    sweep_call_runtime(symbol);
}

let sweep_imports: map = pe_import_new()
if sweep_is_windows {
    sweep_imports = pe_import_use64(sweep_imports, "KERNEL32.DLL", "ExitProcess")
}

let sweep_image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
if sweep_is_windows {
    sweep_image = format_pe64(
        format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
        list.of(
            format_section(".text", format_code | format_readable | format_executable),
            format_section(".rdata", format_data | format_readable),
            format_section(".data", format_data | format_readable | format_writeable),
            format_section(".idata", format_imports | format_readable | format_writeable)
        )
    )
}
format_begin(sweep_image);

if sweep_is_windows {
    format_section_begin(sweep_image, ".text");
} else {
    format_segment_begin(sweep_image, ".text");
}
sweep_start:
    if sweep_is_avx2 {
        sweep_call_runtime(std_cpu_detect_symbol);
        test rax, std_cpu_feature_avx2
        jnz sweep_avx2_supported
        sweep_exit(77);
sweep_avx2_supported:
    }
    // copy：257 个长度 × 32 种源/目标相对对齐。
    xor r12d, r12d
sweep_copy_length:
    xor r13d, r13d
sweep_copy_alignment:
    lea r10, [rel actual_buffer]
    lea r11, [rel reference_buffer]
    xor ecx, ecx
sweep_copy_reset:
    mov eax, ecx
    imul eax, eax, 37
    add eax, 11
    mov byte [r10 + rcx], al
    mov byte [r11 + rcx], al
    add ecx, 1
    cmp ecx, sweep_buffer_size
    jb sweep_copy_reset

    lea r10, [rel reference_buffer + 64]
    add r10, r13
    lea r11, [rel source_data + 15]
    sub r11, r13
    mov r8, r12
    test r8, r8
    jz sweep_copy_reference_done
sweep_copy_reference:
    movzx eax, byte [r11]
    mov byte [r10], al
    add r10, 1
    add r11, 1
    sub r8, 1
    jnz sweep_copy_reference
sweep_copy_reference_done:

    lea r10, [rel actual_buffer + 64]
    add r10, r13
    mov r14, r10
    lea r11, [rel source_data + 15]
    sub r11, r13
    mov r8, r12
    sweep_call_binary(std_memory_copy_symbol);
    cmp rax, r14
    jne sweep_failed_copy

    lea r10, [rel actual_buffer]
    lea r11, [rel reference_buffer]
    mov r8d, sweep_buffer_size
sweep_copy_compare:
    movzx eax, byte [r10]
    cmp al, byte [r11]
    jne sweep_failed_copy
    add r10, 1
    add r11, 1
    sub r8, 1
    jnz sweep_copy_compare

    add r13d, 1
    cmp r13d, sweep_alignment_count
    jb sweep_copy_alignment
    add r12d, 1
    cmp r12d, 257
    jb sweep_copy_length

    // fill：257 个长度 × 32 种目标对齐，value 高位必须被忽略。
    xor r12d, r12d
sweep_fill_length:
    xor r13d, r13d
sweep_fill_alignment:
    lea r10, [rel actual_buffer]
    lea r11, [rel reference_buffer]
    xor ecx, ecx
sweep_fill_reset:
    mov eax, ecx
    imul eax, eax, 29
    add eax, 17
    mov byte [r10 + rcx], al
    mov byte [r11 + rcx], al
    add ecx, 1
    cmp ecx, sweep_buffer_size
    jb sweep_fill_reset

    lea r10, [rel reference_buffer + 64]
    add r10, r13
    mov r8, r12
    test r8, r8
    jz sweep_fill_reference_done
sweep_fill_reference:
    mov byte [r10], 0xa5
    add r10, 1
    sub r8, 1
    jnz sweep_fill_reference
sweep_fill_reference_done:

    lea r10, [rel actual_buffer + 64]
    add r10, r13
    mov r14, r10
    mov r11, 0x1234a5
    mov r8, r12
    sweep_call_binary(std_memory_fill_symbol);
    cmp rax, r14
    jne sweep_failed_fill

    lea r10, [rel actual_buffer]
    lea r11, [rel reference_buffer]
    mov r8d, sweep_buffer_size
sweep_fill_compare:
    movzx eax, byte [r10]
    cmp al, byte [r11]
    jne sweep_failed_fill
    add r10, 1
    add r11, 1
    sub r8, 1
    jnz sweep_fill_compare

    add r13d, 1
    cmp r13d, sweep_alignment_count
    jb sweep_fill_alignment
    add r12d, 1
    cmp r12d, 257
    jb sweep_fill_length

    // move：129 个长度 × -32..32 的全部源/目标距离。
    xor r12d, r12d
sweep_move_length:
    mov r13, -32
sweep_move_distance:
    lea r10, [rel actual_buffer]
    lea r11, [rel reference_buffer]
    xor ecx, ecx
sweep_move_reset:
    mov eax, ecx
    imul eax, eax, 23
    add eax, 7
    mov byte [r10 + rcx], al
    mov byte [r11 + rcx], al
    add ecx, 1
    cmp ecx, sweep_buffer_size
    jb sweep_move_reset

    lea r10, [rel reference_buffer + 192]
    add r10, r13
    lea r11, [rel reference_buffer + 192]
    mov r8, r12
    test r8, r8
    jz sweep_move_reference_done
    cmp r10, r11
    jbe sweep_move_reference_forward
    mov rax, r10
    sub rax, r11
    cmp rax, r8
    jae sweep_move_reference_forward
    add r10, r8
    add r11, r8
sweep_move_reference_backward:
    sub r10, 1
    sub r11, 1
    movzx eax, byte [r11]
    mov byte [r10], al
    sub r8, 1
    jnz sweep_move_reference_backward
    jmp sweep_move_reference_done
sweep_move_reference_forward:
    movzx eax, byte [r11]
    mov byte [r10], al
    add r10, 1
    add r11, 1
    sub r8, 1
    jnz sweep_move_reference_forward
sweep_move_reference_done:

    lea r10, [rel actual_buffer + 192]
    add r10, r13
    mov r14, r10
    lea r11, [rel actual_buffer + 192]
    mov r8, r12
    sweep_call_binary(std_memory_move_symbol);
    cmp rax, r14
    jne sweep_failed_move

    lea r10, [rel actual_buffer]
    lea r11, [rel reference_buffer]
    mov r8d, sweep_buffer_size
sweep_move_compare:
    movzx eax, byte [r10]
    cmp al, byte [r11]
    jne sweep_failed_move
    add r10, 1
    add r11, 1
    sub r8, 1
    jnz sweep_move_compare

    add r13, 1
    cmp r13, 32
    jle sweep_move_distance
    add r12d, 1
    cmp r12d, 129
    jb sweep_move_length

    sweep_exit(0);
sweep_failed_copy:
    sweep_exit(1);
sweep_failed_fill:
    sweep_exit(2);
sweep_failed_move:
    sweep_exit(3);

if sweep_is_runtime {
    std_cpu_emit(test_memory_abi);
    std_memory_emit_runtime(test_memory_abi, "sweep_memory_runtime_state");
} else {
    if sweep_is_avx2 {
        std_cpu_emit(test_memory_abi);
    }
    std_memory_emit_tier(test_memory_abi, test_memory_tier);
}

if sweep_is_windows {
    format_section_end(sweep_image, ".text");
    format_section_begin(sweep_image, ".rdata");
} else {
    format_segment_end(sweep_image, ".text");
    format_segment_begin(sweep_image, ".rodata");
}
source_data:
for value in range(0, 512) {
    db((value * 23 + 7) % 256);
}
if sweep_is_windows {
    format_section_end(sweep_image, ".rdata");
    format_section_begin(sweep_image, ".data");
} else {
    format_segment_end(sweep_image, ".rodata");
    format_segment_begin(sweep_image, ".data");
}
actual_buffer:
for slot in range(0, 64) {
    dq(0);
}
if sweep_is_runtime {
sweep_memory_runtime_state:
    rq(8);
}
reference_buffer:
for slot in range(0, 64) {
    dq(0);
}
if sweep_is_windows {
    format_section_end(sweep_image, ".data");
    format_pe_import_section(sweep_image, ".idata", sweep_imports);
} else {
    format_segment_end(sweep_image, ".data");
}

format_entry_mut(sweep_image, sweep_start)
format_finish(sweep_image);
