# xirasm-lib

`xirasm-lib` is the pure ISA backend library for XIRASM.

Scope:

- x86 encoder backend (`src/x86_encoder/`)
- RISC-V encoder backend and native source/text instruction parser (`src/riscv_encoder/`)
- SPIR-V encoder backend and text support (`src/spirv_encoder/`)
- backend tests and generator/verification scripts

Out of scope:

- assembler symbol tables and labels
- pseudo directives and frontend source control
- runtime executable-page allocation
- C ABI shellcode convenience runners
- Meta VM / frontend language behavior
- object/linker ownership
