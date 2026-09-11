"""Where does instruction encoding time go: per form, or per instruction count?

A source with nothing but instructions spends its time in the encode phase, so this
probe separates the two explanations for a slow one: a fixed cost per instruction
(linear scaling, inherent) against a cost that grows with size (superlinear, a
defect), and a cheap form (`nop`) against a heavy one (AVX2 with a memory operand).

Usage: python tests/perf/encode_profile.py --xirasm <path to xirasm> [--sizes 1000,10000,100000]
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHASE = re.compile(r"phase=(\w+) elapsed_ms=([\d.]+)")

# (label, instruction text) -- one statement per line, repeated
FORMS = (
    ("nop", "nop"),
    ("mov r64, imm", "mov rax, 1"),
    ("add r64, r64", "add rax, rbx"),
    ("vmovdqu ymm, mem", "vmovdqu ymm0, yword [rax + rbx*4 + 64]"),
    ("vpshufb ymm, ymm, ymm", "vpshufb ymm3, ymm3, ymm4"),
)


def phases(xirasm: Path, work: Path, name: str, source: str,
           warmup: bool = True) -> tuple[dict[str, float], float, int, float]:
    """Assemble the probe, optionally once to warm the caches, and time the last run.

    The first run of a large source on this machine costs about twice the second
    one, so a single cold measurement is not a baseline. The cold wall time comes
    back with the warm numbers so the difference stays visible.
    """
    path = work / f"{name}.asm"
    path.write_text(source, encoding="utf-8", newline="\n")
    output = work / f"{name}.bin"
    cold = 0.0
    result = None
    attempts = 2 if warmup else 1
    for attempt in range(attempts):
        start = time.perf_counter()
        result = subprocess.run([str(xirasm), str(path), "-o", str(output), "--trace-phases"],
                                capture_output=True, text=True, errors="replace")
        elapsed = (time.perf_counter() - start) * 1000.0
        if attempt == 0:
            cold = elapsed
    wall = elapsed
    if result is None or result.returncode != 0:
        detail = (result.stdout + result.stderr)[:400] if result else "no run"
        raise SystemExit(f"{name} failed:\n{detail}")
    measured = {phase: float(value) for phase, value in PHASE.findall(result.stdout + result.stderr)}
    return measured, wall, output.stat().st_size, cold


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
    parser.add_argument("--xirasm", type=Path, default=ROOT / "zig-out" / "bin" / "xirasm.exe")
    parser.add_argument("--sizes", default="1000,10000,100000")
    args = parser.parse_args()
    xirasm = args.xirasm.resolve()
    describe_assembler(xirasm)
    sizes = [int(value) for value in args.sizes.split(",")]
    work = ROOT / "zig-out" / "perf-probes" / "encode"
    work.mkdir(parents=True, exist_ok=True)

    print(f"{'form':24} {'count':>7} {'parse ms':>9} {'encode ms':>10} {'us/instr':>9} "
          f"{'wall ms':>9} {'cold ms':>8} {'bytes':>10}")
    previous: dict[str, tuple[int, float]] = {}
    for label, instruction in FORMS:
        for count in sizes:
            source = "\n".join([instruction] * count) + "\nemit.u64(0);\n"
            measured, wall, size, cold = phases(
                xirasm, work, f"{label.replace(' ', '_').replace(',', '')}-{count}", source)
            encode = measured.get("encode", float("nan"))
            parse = measured.get("parse_lower", float("nan"))
            per = encode * 1000.0 / count
            growth = ""
            if label in previous:
                last_count, last_per = previous[label]
                factor = (count / last_count)
                growth = f"  ({per / last_per:.2f}x per instruction over {factor:.0f}x count)"
            previous[label] = (count, per)
            print(f"{label:24} {count:7,} {parse:9.1f} {encode:10.1f} {per:9.3f} "
                  f"{wall:9.0f} {cold:8.0f} {size:10,}{growth}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
