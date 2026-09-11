"""Look for more quadratic paths by doubling a source and reading the growth.

The symbol store was quadratic in the number of declarations, which a doubling test
found in one measurement. This sweep applies the same test to the other shapes a
generated or hand-written source produces: local bindings, labels, label
references, macro invocations, type declarations and data rows. A cost that scales
with the count (2x per doubling) is fine; about 4x per doubling means something is
quadratic in that shape.

Usage: python tests/perf/scaling_sweep.py --xirasm <path> [--sizes 12500,25000]
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHASE = re.compile(r"phase=(\w+) elapsed_ms=([\d.]+)")


def describe_assembler(xirasm: Path) -> None:
    size = xirasm.stat().st_size
    digest = hashlib.sha256(xirasm.read_bytes()).hexdigest()[:12]
    note = "  <-- larger than a release build; measure with -Doptimize=ReleaseSafe" if size > 4_500_000 else ""
    print(f"assembler: {xirasm.name} {size:,} B sha256 {digest}{note}")


def cases(count: int) -> dict[str, str]:
    labels = "\n".join(f"label_{index}:" for index in range(count))
    return {
        "top-level consts": "".join(f"const c{index}: u64 = {index};\n" for index in range(count)),
        "local bindings in one function": (
            "fn holder() -> u64 {\n"
            + "".join(f"    let v{index}: u64 = {index}\n" for index in range(count))
            + "    return 0;\n}\nemit.u64(0);\n"
        ),
        "labels": labels + "\nemit.u64(0);\n",
        "label references": labels + "\n" + "".join(f"dq(label_{index})\n" for index in range(count)),
        "macro invocations": (
            "macro bump(value) {\n    emit.u8(operand.eval(value))\n}\n"
            + "".join(f"bump {index % 251}\n" for index in range(count))
        ),
        "struct declarations": "".join(
            f"struct s{index} {{\n    a: u64\n    b: u32\n}}\n" for index in range(count)
        ) + "\nemit.u64(0);\n",
        "data rows": "".join(f"dq({index})\n" for index in range(count)),
    }


def measure(xirasm: Path, work: Path, name: str, source: str) -> float:
    path = work / f"{name.replace(' ', '_')}.asm"
    path.write_text(source, encoding="utf-8", newline="\n")
    for _ in range(2):
        result = subprocess.run([str(xirasm), str(path), "-o", str(path.with_suffix(".bin")), "--trace-phases"],
                                capture_output=True, text=True, errors="replace")
        if result.returncode != 0:
            detail = (result.stdout + result.stderr).strip().splitlines()
            print(f"  {name}: does not assemble -- {detail[0][:90] if detail else 'no output'}")
            return float("nan")
        measured = {phase: float(value) for phase, value in PHASE.findall(result.stdout + result.stderr)}
    return measured.get("parse_lower", float("nan"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xirasm", type=Path, default=ROOT / "zig-out" / "bin" / "xirasm.exe")
    parser.add_argument("--sizes", default="12500,25000")
    args = parser.parse_args()
    xirasm = args.xirasm.resolve()
    describe_assembler(xirasm)
    sizes = [int(value) for value in args.sizes.split(",")]
    work = ROOT / "zig-out" / "perf-probes" / "scaling"
    work.mkdir(parents=True, exist_ok=True)

    print(f"{'shape':32} {'small ms':>9} {'large ms':>9} {'growth':>8}  verdict")
    for name in cases(sizes[0]):
        times = [measure(xirasm, work, f"{name}-{size}", cases(size)[name]) for size in sizes]
        if any(value != value for value in times):
            continue
        growth = times[1] / max(times[0], 1e-9)
        verdict = "linear or better" if growth < 2.6 else ("superlinear -- investigate" if growth < 4.4 else "quadratic")
        print(f"{name:32} {times[0]:9.1f} {times[1]:9.1f} {growth:7.2f}x  {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
