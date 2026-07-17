// std/core runtime dispatch 的跨平台并发首次发布真机测试。
//
// 8 个执行流先报告 ready，再等待同一 gate；gate 打开后共同竞争空的 feature
// cache 与 target cache。Windows 使用 CreateThread，Linux 使用 CLONE_VM 子进程。

import("format/format.inc");
import("std/core.inc");
x86.use64();

const cpu_concurrency_is_windows: bool = cpu_test_abi == std_core_abi_windows64
const cpu_concurrency_count: u64 = 8
const cpu_linux_stack_size: u64 = 16384
const cpu_linux_stack_total: u64 = cpu_concurrency_count * cpu_linux_stack_size

fn cpu_concurrency_exit(status: u64) {
    if cpu_concurrency_is_windows {
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

let cpu_concurrency_imports: map = pe_import_new()
if cpu_concurrency_is_windows {
    cpu_concurrency_imports = pe_import_use64_many(
        cpu_concurrency_imports,
        "KERNEL32.DLL",
        list.of("ExitProcess", "CreateThread", "WaitForSingleObject", "CloseHandle")
    )
}

let cpu_concurrency_image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
if cpu_concurrency_is_windows {
    cpu_concurrency_image = format_pe64(
        format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
        list.of(
            format_section(".text", format_code | format_readable | format_executable),
            format_section(".data", format_data | format_readable | format_writeable),
            format_section(".idata", format_imports | format_readable | format_writeable)
        )
    )
}
format_begin(cpu_concurrency_image);

if cpu_concurrency_is_windows {
    format_section_begin(cpu_concurrency_image, ".text");
} else {
    format_segment_begin(cpu_concurrency_image, ".text");
}
cpu_concurrency_start:
    if cpu_concurrency_is_windows {
        lea r12, [rel cpu_concurrency_handles]
        lea r13, [rel cpu_concurrency_results]
        mov r14d, cpu_concurrency_count
cpu_windows_create_loop:
        xor ecx, ecx
        xor edx, edx
        lea r8, [rel cpu_windows_thread]
        mov r9, r13
        sub rsp, 56
        mov qword [rsp + 32], 0
        mov qword [rsp + 40], 0
        call [rel CreateThread]
        add rsp, 56
        test rax, rax
        jz cpu_concurrency_failed_setup
        mov qword [r12], rax
        add r12, 8
        add r13, 8
        sub r14d, 1
        jnz cpu_windows_create_loop

cpu_windows_wait_ready:
        cmp dword [rel cpu_concurrency_ready], cpu_concurrency_count
        jae cpu_concurrency_open_gate
        pause
        jmp cpu_windows_wait_ready
cpu_concurrency_open_gate:
        mov eax, 1
        xchg dword [rel cpu_concurrency_gate], eax

        lea r12, [rel cpu_concurrency_handles]
        mov r13d, cpu_concurrency_count
cpu_windows_join_loop:
        mov rcx, qword [r12]
        mov edx, -1
        sub rsp, 40
        call [rel WaitForSingleObject]
        add rsp, 40
        test eax, eax
        jnz cpu_concurrency_failed_join
        mov rcx, qword [r12]
        sub rsp, 40
        call [rel CloseHandle]
        add rsp, 40
        test eax, eax
        jz cpu_concurrency_failed_join
        add r12, 8
        sub r13d, 1
        jnz cpu_windows_join_loop
    } else {
        // 为每个 CLONE_VM 子进程分配独立 16 KiB 栈。
        xor edi, edi
        mov esi, cpu_linux_stack_total
        mov edx, 3
        mov r10d, 0x22
        mov r8, -1
        xor r9d, r9d
        mov eax, 9
        syscall
        test rax, rax
        js cpu_concurrency_failed_setup
        mov r15, rax

        xor r12d, r12d
        lea r13, [rel cpu_concurrency_handles]
cpu_linux_clone_loop:
        mov rsi, r12
        add rsi, 1
        shl rsi, 14
        add rsi, r15
        mov edi, 0x111
        xor edx, edx
        xor r10d, r10d
        xor r8d, r8d
        mov eax, 56
        syscall
        test rax, rax
        jz cpu_linux_child
        js cpu_concurrency_failed_setup
        mov qword [r13], rax
        add r13, 8
        add r12d, 1
        cmp r12d, cpu_concurrency_count
        jb cpu_linux_clone_loop

cpu_linux_wait_ready:
        cmp dword [rel cpu_concurrency_ready], cpu_concurrency_count
        jae cpu_linux_open_gate
        pause
        jmp cpu_linux_wait_ready
cpu_linux_open_gate:
        mov eax, 1
        xchg dword [rel cpu_concurrency_gate], eax

        lea r13, [rel cpu_concurrency_handles]
        mov r14d, cpu_concurrency_count
cpu_linux_join_loop:
        mov rdi, qword [r13]
        lea rsi, [rel cpu_linux_wait_status]
        xor edx, edx
        xor r10d, r10d
        mov eax, 61
        syscall
        cmp rax, qword [r13]
        jne cpu_concurrency_failed_join
        cmp dword [rel cpu_linux_wait_status], 0
        jne cpu_concurrency_failed_join
        add r13, 8
        sub r14d, 1
        jnz cpu_linux_join_loop

        mov rdi, r15
        mov esi, cpu_linux_stack_total
        mov eax, 11
        syscall
        test rax, rax
        jnz cpu_concurrency_failed_join
    }

cpu_concurrency_check:
    call std_cpu_detect
    mov r10d, 0x31
    test rax, std_cpu_feature_avx2
    jz cpu_concurrency_expected_ready
    mov r10d, 0x32
cpu_concurrency_expected_ready:
    lea r12, [rel cpu_concurrency_results]
    mov r13d, cpu_concurrency_count
cpu_concurrency_result_loop:
    cmp qword [r12], r10
    jne cpu_concurrency_failed_result
    add r12, 8
    sub r13d, 1
    jnz cpu_concurrency_result_loop

    cmp dword [rel cpu_concurrency_ready], cpu_concurrency_count
    jne cpu_concurrency_failed_result
    cmp qword [rel cpu_concurrency_state], 0
    jns cpu_concurrency_failed_result
    cmp qword [rel cpu_concurrency_state + 8], 0
    je cpu_concurrency_failed_result
    cpu_concurrency_exit(0);

cpu_concurrency_failed_setup:
    mov eax, 1
    xchg dword [rel cpu_concurrency_gate], eax
    cpu_concurrency_exit(1);
cpu_concurrency_failed_join:
    cpu_concurrency_exit(2);
cpu_concurrency_failed_result:
    cpu_concurrency_exit(3);

if cpu_concurrency_is_windows {
cpu_windows_thread:
    mov r10, rcx
    lock add dword [rel cpu_concurrency_ready], 1
cpu_windows_thread_wait:
    cmp dword [rel cpu_concurrency_gate], 0
    jne cpu_windows_thread_go
    pause
    jmp cpu_windows_thread_wait
cpu_windows_thread_go:
    mov rcx, r10
    mov edx, 0x2222
    mov r8d, 0x3333
    sub rsp, 40
    call cpu_concurrency_dispatch
    add rsp, 40
    ret
} else {
cpu_linux_child:
    lock add dword [rel cpu_concurrency_ready], 1
cpu_linux_child_wait:
    cmp dword [rel cpu_concurrency_gate], 0
    jne cpu_linux_child_go
    pause
    jmp cpu_linux_child_wait
cpu_linux_child_go:
    lea rdi, [rel cpu_concurrency_results]
    mov rax, r12
    shl rax, 3
    add rdi, rax
    mov esi, 0x2222
    mov edx, 0x3333
    call cpu_concurrency_dispatch
    xor edi, edi
    mov eax, 60
    syscall
}

std_cpu_emit(cpu_test_abi);
std_dispatch_emit_avx2(cpu_test_abi, std_core_dispatch_runtime, "cpu_concurrency_dispatch", "cpu_concurrency_state", "cpu_concurrency_target_baseline", "cpu_concurrency_target_avx2");

cpu_concurrency_target_baseline:
    if cpu_concurrency_is_windows {
        cmp rdx, 0x2222
        jne cpu_concurrency_target_bad
        cmp r8, 0x3333
        jne cpu_concurrency_target_bad
        mov qword [rcx], 0x31
    } else {
        cmp rsi, 0x2222
        jne cpu_concurrency_target_bad
        cmp rdx, 0x3333
        jne cpu_concurrency_target_bad
        mov qword [rdi], 0x31
    }
    mov eax, 0x31
    ret
cpu_concurrency_target_avx2:
    if cpu_concurrency_is_windows {
        cmp rdx, 0x2222
        jne cpu_concurrency_target_bad
        cmp r8, 0x3333
        jne cpu_concurrency_target_bad
        mov qword [rcx], 0x32
    } else {
        cmp rsi, 0x2222
        jne cpu_concurrency_target_bad
        cmp rdx, 0x3333
        jne cpu_concurrency_target_bad
        mov qword [rdi], 0x32
    }
    mov eax, 0x32
    ret
cpu_concurrency_target_bad:
    if cpu_concurrency_is_windows {
        mov qword [rcx], 0xff
    } else {
        mov qword [rdi], 0xff
    }
    mov eax, 0xff
    ret

if cpu_concurrency_is_windows {
    format_section_end(cpu_concurrency_image, ".text");
    format_section_begin(cpu_concurrency_image, ".data");
} else {
    format_segment_end(cpu_concurrency_image, ".text");
    format_segment_begin(cpu_concurrency_image, ".data");
}
cpu_concurrency_state:
    dq(0, 0);
cpu_concurrency_results:
for cpu_result_index in range(0, cpu_concurrency_count) {
    dq(0);
}
cpu_concurrency_handles:
for cpu_handle_index in range(0, cpu_concurrency_count) {
    dq(0);
}
cpu_concurrency_gate:
    dd(0);
cpu_concurrency_ready:
    dd(0);
cpu_linux_wait_status:
    dq(0);

if cpu_concurrency_is_windows {
    format_section_end(cpu_concurrency_image, ".data");
    format_pe_import_section(cpu_concurrency_image, ".idata", cpu_concurrency_imports);
} else {
    format_segment_end(cpu_concurrency_image, ".data");
}

format_entry_mut(cpu_concurrency_image, cpu_concurrency_start)
format_finish(cpu_concurrency_image);
