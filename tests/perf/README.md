# Include and lowering cost probes

These two scripts measure where assembly time goes when a source imports a large
include tree, and they are the before/after gate for any work on that cost. They
only need a built `xirasm`; nothing here is part of the normal test run.

```powershell
python tests/perf/include_profile.py  --xirasm zig-out/bin/xirasm.exe
python tests/perf/lowering_control.py --xirasm zig-out/bin/xirasm.exe
```

`include_profile.py` profiles the transitive include closure of a mixed project
(A64 macros, the format layer, two platform libraries, two header partitions). It
reports the cost of importing each file plus its closure, the marginal cost of each
entry (leave-one-out, the column to read), and a controlled comparison of one
statement per entry against one table statement.

`lowering_control.py` writes two sources with the same declarations -- one whose
function bodies hold as many statements as the generated A64 tree, one whose bodies
are empty -- to separate the cost of a declaration from the cost of its body.

Baseline on the development machine (Zig 0.17, ReleaseSafe, files page-cached):

| probe | parse_lower |
| --- | ---: |
| empty source | 0.07 ms |
| `format/format.inc` (159 KB) | 26.8 ms |
| `os/android/defs.inc` (1.0 MB) | 12.2 ms |
| `os/android/imports.inc` (0.5 MB) | 73.6 ms |
| `os/win32/imports/kernel32.inc` | 33.9 ms |
| `os/win32/imports.inc` (339 files, 94 MB) | 593 ms |
| `arm/a64-macros.inc` (2.55 MB generated) | 153 ms |
| mixed project | 220 ms |
| `tests/format/android_gl_demo/gl-demo-so-aarch64.asm` | 1711 ms (includes are 13%) |

Two facts those numbers establish: file reading is not the cost (`read_source` is
0.3 ms regardless of size), and function bodies are already lowered when they are
called, so their cost is parsing. Keep both scripts in step with the engine: they
are the only measurement of this path in the repository.

## Instruction-heavy sources: encoding, not includes

`tests/perf/x86_100k.asm` (12,500 iterations of eight AVX2 instructions) is the
other axis: a source that imports almost nothing but encodes a lot.

| phase | time |
| --- | ---: |
| parse_lower | 123.2 ms |
| **encode** | **1,039.5 ms** (10.4 us per instruction) |
| fixup, layout, materialize, write | 7.6 ms |
| wall | 1,302 ms (787,501 B output) |

Encoding is 80% of the run, so include work does not move this number at all. Keep
the two axes apart when measuring: parsing costs microseconds per statement,
encoding costs microseconds per instruction, and the format layer adds its own cost
on top (PE more than ELF).

## Encoding cost per form (warm)

`encode_profile.py` repeats one instruction per line at 1K/10K/100K and reports the
encode phase. Warm measurements, 100,000 instructions:

| form | encode | per instruction |
| --- | ---: | ---: |
| `nop` | 90.1 ms | 0.90 us |
| `mov rax, 1` | 232.9 ms | 2.33 us |
| `add rax, rbx` | 275.8 ms | 2.76 us |
| `vpshufb ymm3, ymm3, ymm4` | 406.9 ms | 4.07 us |
| `vmovdqu ymm0, yword [rax + rbx*4 + 64]` | 485.3 ms | 4.85 us |

The cost is linear in the instruction count (1.00-1.02x per instruction across a ten
times larger input), it depends on the form rather than on how many distinct forms
are mixed, and it is dominated by the per-instruction constant, not by scaling.

**Measure warm.** The first run of a large source here costs about twice the second
one (the repository's own fixture: 1,039 ms first, 537.9 ms after), so the probe
assembles each case twice and reports the second run while printing the cold wall
time next to it. A single cold measurement is not a baseline.

## Measure a release build, and say which one

Debug and ReleaseSafe differ by about 2x here, and their sizes give the binary away:
a Debug `xirasm.exe` is around 7.1 MB, a ReleaseSafe one around 3.19 MB. Note also
that `zig build test` installs the Debug binary into `zig-out`, so run
`zig build -Doptimize=ReleaseSafe` before measuring anything. Every probe prints the
binary it measured and warns when the file is larger than a release build.

Declaring many top-level constants used to be quadratic, because each declaration
scanned the whole symbol store to reject duplicates. Measured with matched release
binaries (3,185,664 B before, 3,187,712 B after):

| probe | before | after |
| --- | ---: | ---: |
| 50,000 top-level consts | 4,722.6 ms | 73.0 ms |
| `os/win32/imports.inc` | 580.7 ms | 219.8 ms |
| `os/win32/defs.inc` | 489.2 s | 3.42 s |
| `os/win32/comdefs.inc` | 476.4 s | 1.03 s |
| `arm/a64-macros.inc` (control) | 232.7 ms | 196.7 ms |
