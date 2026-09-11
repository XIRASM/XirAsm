"""Is the include cost the lowering of function bodies, or the declarations?

The A64 encoder tree is 2,334 functions holding 42,444 statements, and importing
it costs 153 ms even when nothing is ever called. This writes two sources with the
same declarations: one where every function body holds the same number of
statements as the real tree, and one where the bodies are empty. If the second is
much cheaper, the cost is the eager lowering of bodies that are never called, and
deferring that lowering is the optimisation.

Usage: python lowering_control.py --xirasm <path to xirasm>
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "zig-out" / "perf-probes"
PHASE = re.compile(r"phase=(\w+) elapsed_ms=([\d.]+)")

FUNCTIONS = 2334
FORMS = 6


def filled_source() -> str:
    lines = ["// synthetic encoder tree: same shape as the generated A64 tree"]
    for index in range(FUNCTIONS):
        lines.append(f"fn f{index}(a: u64) -> u64 {{")
        for form in range(FORMS):
            lines.append(f"    if a == {form} {{")
            lines.append(f"        return 0x{index:04x} | ({form} << 8);")
            lines.append("    }")
        lines.append("    return 0;")
        lines.append("}")
    lines.append("emit.u64(0);")
    return "\n".join(lines) + "\n"


def empty_source() -> str:
    lines = ["// the same declarations, bodies lowered to nothing"]
    for index in range(FUNCTIONS):
        lines.append(f"fn f{index}(a: u64) -> u64 {{")
        lines.append("    return 0;")
        lines.append("}")
    lines.append("emit.u64(0);")
    return "\n".join(lines) + "\n"


def statements(text: str) -> int:
    return sum(1 for line in text.splitlines()
               if (stripped := line.strip()) and not stripped.startswith("//")
               and stripped not in ("{", "}", "};"))


def measure(xirasm: Path, work: Path, source: str, name: str) -> float:
    path = work / f"{name}.asm"
    path.write_text(source, encoding="utf-8", newline="\n")
    result = subprocess.run([str(xirasm), str(path), "-o", str(work / f"{name}.bin"), "--trace-phases"],
                            capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"{name} failed:\n" + (result.stdout + result.stderr)[:500])
    for phase, value in PHASE.findall(result.stdout + result.stderr):
        if phase == "parse_lower":
            return float(value)
    raise SystemExit(f"{name}: no parse_lower phase reported")


def describe_assembler(xirasm: Path) -> None:
    """Say which binary is being measured: Debug and ReleaseSafe differ by about 2x."""
    size = xirasm.stat().st_size
    digest = hashlib.sha256(xirasm.read_bytes()).hexdigest()[:12]
    note = ""
    if size > 4_500_000:
        note = "  <-- larger than a release build; measure with -Doptimize=ReleaseSafe"
    print(f"assembler: {xirasm.name} {size:,} B sha256 {digest}{note}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xirasm", type=Path, default=ROOT / "zig-out/bin/xirasm.exe")
    args = parser.parse_args()
    describe_assembler(args.xirasm.resolve())
    WORK.mkdir(parents=True, exist_ok=True)

    baseline = measure(args.xirasm, WORK, "emit.u64(0);\n", "baseline")
    filled = filled_source()
    empty = empty_source()
    filled_ms = measure(args.xirasm, WORK, filled, "filled") - baseline
    empty_ms = measure(args.xirasm, WORK, empty, "empty") - baseline

    print(f"baseline (empty source)        parse_lower {baseline:8.2f} ms")
    print(f"bodied functions               parse_lower {filled_ms:8.2f} ms   "
          f"functions={FUNCTIONS:,} statements={statements(filled):,}")
    print(f"declarations only              parse_lower {empty_ms:8.2f} ms   "
          f"functions={FUNCTIONS:,} statements={statements(empty):,}")
    print(f"\nstatement shape: {statements(filled) / FUNCTIONS:.1f} statements per function")
    print(f"bodies cost {filled_ms - empty_ms:.1f} ms of the {filled_ms:.1f} ms "
          f"({100 * (filled_ms - empty_ms) / max(filled_ms, 1e-9):.0f}%)")
    print(f"ratio: {(filled_ms - baseline) / max(empty_ms, 1e-9):.1f}x cheaper without body lowering")
    print("\nreal A64 tree for reference: 2,549,740 B, 42,444 statements, 2,334 functions, 153 ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
