"""Measure what include cost is actually made of.

Part 1 profiles the transitive include closure of a realistic project: one probe
per file, timed through `--trace-phases`, reported against the statement count and
byte size of that file.

Part 2 is a controlled comparison of the two ways the same logical content can be
written: one statement per entry (an if chain, which is what the generated A64
encoders look like) against one statement holding every entry (a table).

Usage: python include_profile.py --xirasm <path to xirasm>
"""
from __future__ import annotations

import argparse
import hashlib
import re
import statistics
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INCLUDE = ROOT / "include"
IMPORT = re.compile(r'^\s*(?:import|include)\("([^"]+)"\)')
PHASE = re.compile(r"phase=(\w+) elapsed_ms=([\d.]+)")

# A realistic mixed project: A64 macros, the format layer, a couple of platform
# libraries, and the header partitions the renderer example pulls in.
ENTRY = """import("arm/a64-macros.inc")
import("format/format.inc")
import("os/android/imports/libandroid.inc")
import("os/android/imports/libEGL.inc")
import("os/android/imports/libGLESv2.inc")
import("os/android/defs/native_activity.inc")
import("os/android/defs/native_window.inc")
emit.u64(0);
"""


def closure(entry: str) -> list[str]:
    seen: list[str] = []
    pending = [line for line in entry.splitlines() if (match := IMPORT.match(line)) for line in [match.group(1)]]
    while pending:
        name = pending.pop(0)
        if name in seen:
            continue
        path = INCLUDE / name
        if not path.is_file():
            continue
        seen.append(name)
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = IMPORT.match(line)
            if match and match.group(1) not in seen:
                pending.append(match.group(1))
    return seen


def statements(text: str) -> int:
    """Lines that carry a statement or declaration, ignoring blank and comment lines."""
    count = 0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if stripped in ("{", "}", "};"):
            continue
        count += 1
    return count


def parse_lower(xirasm: Path, work: Path, source: str, name: str) -> float:
    path = work / f"{name}.asm"
    path.write_text(source, encoding="utf-8", newline="\n")
    result = subprocess.run([str(xirasm), str(path), "-o", str(work / f"{name}.bin"), "--trace-phases"],
                            capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        return float("nan")
    for phase, value in PHASE.findall(result.stdout + result.stderr):
        if phase == "parse_lower":
            return float(value)
    return float("nan")


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
    xirasm = args.xirasm.resolve()
    describe_assembler(xirasm)

    # The harness temp area carries restrictive ACLs, so probes live in the
    # workspace instead.
    work = ROOT / ".local" / "ndk-packaging-dsh-2026-09-10" / "verify" / "perf-run"
    if work.exists():
        import shutil
        shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True, exist_ok=True)
    if True:
        baseline = parse_lower(xirasm, work, "emit.u64(0);\n", "baseline")
        print(f"baseline (no include): parse_lower {baseline:.2f} ms\n")

        print("== part 1: the include closure of a mixed project ==")
        print(f"{'bytes':>9} {'stmts':>7} {'ms':>8} {'ms/MB':>7} {'us/stmt':>8}  file (cost of importing it plus its closure)")
        rows = []
        for name in sorted(closure(ENTRY)):
            text = (INCLUDE / name).read_text(encoding="utf-8", errors="replace")
            elapsed = parse_lower(xirasm, work, f'import("{name}")\nemit.u64(0);\n', "probe") - baseline
            rows.append((name, len(text.encode()), statements(text), elapsed))
        for name, size, count, elapsed in sorted(rows, key=lambda row: -row[3]):
            print(f"{size:9,} {count:7,} {elapsed:8.2f} "
                  f"{elapsed / max(size / 1e6, 1e-6):7.1f} "
                  f"{elapsed * 1000 / max(count, 1):8.1f}  {name}")
        bytes_total = sum(row[1] for row in rows)
        statements_total = sum(row[2] for row in rows)
        print(f"\n{len(rows)} files, {bytes_total:,} bytes, {statements_total:,} statements")
        print("(the per-file column double counts nested closures; the marginal table below is the "
              "one to read)")
        project = parse_lower(xirasm, work, ENTRY, "project") - baseline
        print(f"\nwhole project, one run: {project:.1f} ms")
        print(f"{'ms delta':>9}  entry left out")
        lines = ENTRY.strip().splitlines()
        for index, line in enumerate(lines):
            match = IMPORT.match(line)
            if not match:
                continue
            without = "\n".join(lines[:index] + lines[index + 1:]) + "\n"
            other = parse_lower(xirasm, work, without, f"without-{index}") - baseline
            print(f"{project - other:9.1f}  {match.group(1)}")

        print("\n== part 2: one statement per entry (if chain) against one table statement ==")
        entries = 1000
        chain = ["let hits: u64 = 0"]
        for index in range(entries):
            # A block has to open with '{' on its own statement line, so the entry
            # spans three lines rather than one.
            chain += [f"if hits == {index + 1} {{", "    hits = hits + 1;", "}"]
        chain_source = "\n".join(chain) + "\nemit.u64(hits);\n"
        table_source = ("const table: list = list.of(\n    "
                        + ", ".join(str(index) for index in range(entries))
                        + "\n)\nemit.u64(len(table));\n")
        data_rows = "\n".join(f"dq({index})" for index in range(entries)) + "\nemit.u64(0);\n"
        for label, source in (("1000 if statements", chain_source),
                              ("1000 entries in one list.of", table_source),
                              ("1000 dq data rows", data_rows)):
            elapsed = parse_lower(xirasm, work, source, label.split()[0])
            count = statements(source)
            print(f"{label:30} statements={count:6,}  parse_lower={elapsed - baseline:8.2f} ms  "
                  f"{(elapsed - baseline) * 1000 / count:6.1f} us/statement")

        print("\n== part 3: what the A64 generated encoders cost per form ==")
        path = INCLUDE / "arm/a64/generated/instructions.inc"
        text = path.read_text(encoding="utf-8", errors="replace")
        conditionals = len(re.findall(r"^\s*if \(.*\) \{$", text, re.MULTILINE))
        returns = len(re.findall(r"^\s*return 0x", text, re.MULTILINE))
        functions = len(re.findall(r"^fn ", text, re.MULTILINE))
        bytes_total = len(text.encode())
        elapsed = parse_lower(xirasm, work, 'import("arm/a64/generated/instructions.inc")\nemit.u64(0);\n', "a64")
        per_form = (elapsed - baseline) / max(returns, 1)
        print(f"bytes={bytes_total:,} statements={statements(text):,} functions={functions:,} "
              f"selectors={conditionals:,} forms={returns:,}")
        print(f"parse_lower={elapsed - baseline:.1f} ms  ->  {per_form * 1000:.1f} us per form")
        print(f"if the same 4360 forms were table rows: forms would stop being statements, "
              f"leaving ~{functions + 10:,} statements "
              f"(ratio {statements(text) / max(functions + 10, 1):.1f}x fewer)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
