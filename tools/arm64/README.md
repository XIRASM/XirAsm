# A64 Generation

`rules/b1.json` through `rules/b4.json` and `rules/e1.json` through `rules/e4.json`
contain normalized forms tied to the pinned
Arm source inventory. `normalize_a64.py` adapts the translation rules without
executing their Python source. It records every selected XML entry and rule
alternative, checks field ownership, and rejects unresolved mappings.

```text
python tools/arm64/normalize_a64.py --batch B2 --inventory <inventory.json> --xml <a64-xml-directory> --rules <translation-rules-directory> --output tools/arm64/rules/b2.json
python tools/arm64/generate_a64.py
python tools/arm64/generate_a64.py --check
python tests/isa/arm/test_a64_generation.py
python tests/isa/arm/check_a64_generated.py --sync --clang <clang> --objcopy <llvm-objcopy>
```

The emitter reads all eight batches together and gives each mnemonic one API and
macro owner (conditional branches use `b.eq`, `b.ne`, etc.). `arm/a64.inc` and `arm/a64-macros.inc` are the shared entry
points. The earlier B2 entry points forward to them.

The differential runner checks direct calls and macros against Clang, samples
register roles, enumerates finite immediate domains, and verifies rejection,
capture forwarding, and single evaluation. `--batch B2` restricts its forms;
`--phase rejections` reruns only rejection and capture checks after a positive
run. `--phase smoke` compares one case per form without the boundary/rejection
matrix. Reports distinguish these phases. `--output`
retains test artifacts in a new directory; the default uses a temporary one.
`--sync` copies only the new A64 includes beside the selected release executable
and verifies their contents. DSL work does not require rebuilding the compiler.

Clang 22 does not accept the Arm-documented optional `LSL #0` on byte MOVI.
The runner tests that syntax in XIRASM and uses the equivalent omitted-modifier
syntax for the oracle. This exception is explicit in `make_case`.

Record counts include aliases and multiple encodings. They do not count unique
mnemonics, prove whole-architecture coverage, or imply that every encoding can
execute on a given device. Source feature expressions are retained; selecting
device capabilities is separate from generating instruction words.

## Memory And Literal Operands

The generated B3 memory library covers 369 pinned source records. Use
`--batch B3` with the normalizer or differential runner to select that batch.
Run `tests/isa/arm/check_a64_b3_edges.py --clang <clang> --objcopy <llvm-objcopy>`
for independent literal, capture, memory and rejection cases.

Memory descriptors are `a64_mem(base, offset)`, `a64_pre(base, offset)`, and
`a64_index(base, index, extend, amount)`. Bases are X0-X30 or SP. Register
offsets use UXTW/SXTW with W registers or LSL/SXTX with X registers; an amount
of -1 denotes an omitted shift. Each instruction checks its own scaling, range
and overlap restrictions. Post-index offsets are separate operands following
`a64_mem(base, 0)`. Structure lanes use `a64_lanelist(names, index)`.

Literal loads accept `#expression` as a byte displacement, a bare label name
as a deferred target, or a captured address expression such as
`label_addr(label) + ADDEND`. Use `a64_rel(displacement)`, `a64_target(name)`,
or `a64_address(address)` for direct calls. Deferred targets are resolved and
range-checked after layout; `_word` functions take resolved displacements.
Captured expressions retain caller bindings and are evaluated once per reached
instruction. A bare identifier in the literal position denotes a label; use
an explicit expression such as `(ADDRESS)` for a captured address binding.

## Scalar, Control And System Operands

B4 adds 257 pinned records and 1196 forms. B1-B4 together contain 1144 records
and 3592 forms. Integer, SIMD and memory overloads share the same mnemonic owner.
MOV selects MOVZ, MOVN or logical-immediate encoding as appropriate. Register
roles distinguish SP/WSP from XZR/WZR, and shifts/extensions validate their widths.

Branches and ADR use the same displacement/target descriptors as literal loads.
ADRP targets subtract the page-aligned instruction address from the page-aligned
destination. An explicit `#displacement` or `a64_rel` is already a byte delta
and must be a multiple of 4096. Conditional branches use `b.eq target` naturally
or `a64_b_cond(list.of(a64_cond("eq"), a64_target("target")))` directly.

Named system operands use `a64_name`, C0-C15 use `a64_control`, and system
registers use `a64_sysreg`. The latter accepts generic `S2/S3_op1_Cn_Cm_op2`
spellings and 663 fixed names from the pinned open register data, with named
read/write access validation. Parameterized names that cannot be resolved to a
fixed encoding remain listed in the B4 manifest; use generic spellings for them.
No device capability or privilege check is implied.

B4 normalization also reads the matching sibling `SysReg_xml_*` package for
TLBI Rt restrictions and `AARCHMRS_OPENSOURCE_*` package for `Registers.json`.
Their source hashes are retained. TLBI operations requiring Rt=31 reject other
registers. The oracle omits explicit XZR for those names and adds XZR where
Clang requires a register but Arm permits its omission.

The differential oracle enables the extensions needed by the pinned system
operand tables. This does not add SVE/SME instruction families to the DSL.
Run `tests/isa/arm/check_a64_b4_edges.py --clang <clang> --objcopy <llvm-objcopy>`
for independent aliases, system access, deferred branches and cross-page ADRP.

## Pinned Source Inventory

The original baseline remains 1144 records; `scope.json` preserves that original
inventory queue. `extension-batches.json` adds disjoint, explicit record sets:

| Batch | Features | Records | Forms |
| --- | --- | ---: | ---: |
| E1 | AES, SHA1/256/512/3, SM3/SM4, CRC32 | 39 | 39 |
| E2 | LSE, LRCPC/LRCPC2, LOR | 257 | 257 |
| E3 | FP16, DotProd, RDM, FHM, FCMA, BF16, I8MM, FRINTTS, JSCVT | 217 | 333 |
| E4 | PAuth, BTI, MTE/MTE2, FlagM/FlagM2, SB, DGH, RAS, BFC | 86 | 137 |

The combined library has 1743 source records, 4358 forms and 778 mnemonic owners.
The normalizer and differential runner accept `--batch E1` through `--batch E4`.
The same default entry points include all batches. No native compiler ISA backend
or Python runtime is needed to use the shipped DSL includes.

Dot-product element groups use natural `v2.4b[index]` / `v2.2h[index]` syntax,
or `a64_lane("v2.4b", index)` / `a64_lane("v2.2h", index)`. These descriptors
are distinct from single-byte/halfword lanes. CASP validates even first registers
and consecutive pairs. MTE tag-store writeback follows its own operand rules;
ordinary load/store overlap restrictions must not be applied indiscriminately.

`check_a64_extension_edges.py` contains independent extension, register-pair,
grouped-lane, capture and writeback regressions. SVE/SME, A32/T32 and newer
optional features outside the explicit extension batches remain out of scope.

The shared source reader remains part of the production pipeline. It requires
Python 3.11 or later and the dependencies in `requirements.txt`. Supply the
extracted opensource A-profile 2026-06 package containing `Instructions.json`,
`Features.json` and `schema/`. The source lock records metadata, input hashes,
schema-tree hash and A64 node counts. Review source and lock changes together.

```text
python tools/arm64/inventory.py --source-root <package-directory> --output <inventory-directory>
python tools/arm64/inventory.py --source-root <package-directory> --output <inventory-directory> --check
python tests/isa/arm/test_official_inventory.py
```

Use a dedicated output directory outside the source package. The inventory
preserves complete A64 instruction and alias identities, ancestry, constraints,
assembly grammar, operations and feature expressions. It includes a historical
five-form `pilot.json` mapping artifact; current encoding coverage comes from
the B1-B4/E1-E4 rules and generated manifest, not that pilot artifact.

A32/T32 are outside this pipeline. Unknown conditions and deferred records remain
visible. The reader checks source drift, malformed structures, missing
references and contradictory fields. Should-be bits remain distinct from hard
fixed bits; unspecified bits are not silently filled with zero.

The retired hand-written encoder and its pilot emitter are no longer shipped.
Current generation uses only `normalize_a64.py` and `generate_a64.py`.
See `NOTICE` and `MPL-2.0.txt` for source and adaptation notices.
