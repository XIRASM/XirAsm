#!/usr/bin/env python3
"""Check every generated Android constant and offset against clang.

`generate_android_constants.py` parses the NDK headers itself. This checker takes
the numbers that generator produced and hands them back to the compiler as
`_Static_assert`s, for the 64-bit and the 32-bit data models, so a wrong value in
either direction fails the build of the assertion file rather than a program that
was assembled six months later.

usage:
  python tests/os/validate_android_constants.py --ndk <ndk root> [--catalog include/os/android]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONSTANT = re.compile(r"^const (android_[A-Za-z0-9_]+): u64 = (\d+)$")
HEADER = re.compile(r"^// Generated Android constants from NDK header (\S+)\.$")
LAYOUT = re.compile(r"^// (struct|union|typedef) (\w+): ")
LONG_ONLY = "// 64-bit data models only"
TARGETS = {"64": "aarch64-linux-android{api}", "32": "armv7a-linux-androideabi{api}"}


def load(partition: Path) -> tuple[str, list[tuple[str, int, bool]], list[dict]]:
    """Return the header name, its constants, and its layout blocks.

    A block starts with a comment that carries both the layout key and the way C
    has to spell that type: a tag needs `struct X`, a typedef name stands alone.
    A constant preceded by the 64-bit marker is skipped for the 32-bit model,
    because its expression leans on `long` being 64 bits wide.
    """
    header, constants, layouts, current, long_only = "", [], [], None, False
    for line in partition.read_text(encoding="utf-8").splitlines():
        match = HEADER.match(line)
        if match:
            header = match.group(1)
            continue
        if line.startswith(LONG_ONLY):
            long_only = True
            continue
        match = LAYOUT.match(line)
        if match:
            kind, key = match.group(1), match.group(2)
            current = {"key": key, "c": key if kind == "typedef" else f"{kind} {key}", "fields": {}}
            layouts.append(current)
            continue
        match = CONSTANT.match(line)
        if not match:
            continue
        name, value = match.group(1), int(match.group(2))
        if not name.startswith("android_layout_"):
            constants.append((name, value, long_only))
            long_only = False
            continue
        if current is None:
            raise SystemExit(f"{partition}: layout constant outside a layout block: {name}")
        rest = name[len("android_layout_"):]
        if not rest.startswith(current["key"] + "_"):
            raise SystemExit(f"{partition}: {name} does not belong to layout {current['key']}")
        suffix = rest[len(current["key"]) + 1:]
        size = re.fullmatch(r"size(64|32)", suffix)
        if size:
            current[f"size{size.group(1)}"] = value
            continue
        offset = re.fullmatch(r"(.+)_offset(64|32)", suffix)
        if not offset:
            raise SystemExit(f"{partition}: unparsable layout constant {name}")
        current["fields"].setdefault(offset.group(1), {})[f"offset{offset.group(2)}"] = value
    if not header:
        raise SystemExit(f"{partition}: no header line found")
    return header, constants, layouts


def strip_prefix(header: str, name: str) -> str:
    """Recover the C spelling from the generated XIRASM constant name."""
    stem = re.sub(r"[^A-Za-z0-9_]", "_", Path(header).stem).lower()
    prefix = f"android_{stem}_"
    if not name.startswith(prefix):
        raise SystemExit(f"{name}: does not carry the {prefix} prefix of {header}")
    return name[len(prefix):]


def render(header: str, constants: list[tuple[str, int, bool]], layouts: list[dict], model: str) -> str:
    lines = [f"// Static assertions generated from {header}; compiled by the NDK clang.",
             "#include <stddef.h>",
             f"#include <android/{header}>",
             ""]
    for name, value, long_only in constants:
        if long_only and model == "32":
            continue
        c_name = strip_prefix(header, name)
        lines.append(f'_Static_assert((unsigned long long)({c_name}) == {value}ULL, "{c_name}");')
    for row in layouts:
        c_type = row["c"]
        if f"size{model}" in row:
            lines.append(f'_Static_assert(sizeof({c_type}) == {row[f"size{model}"]}ULL, "{c_type} size");')
        for field, offsets in sorted(row.get("fields", {}).items()):
            if f"offset{model}" in offsets:
                lines.append(f'_Static_assert(offsetof({c_type}, {field}) == {offsets[f"offset{model}"]}ULL, '
                             f'"{c_type}.{field}");')
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, default=ROOT / "include/os/android")
    parser.add_argument("--api", type=int, default=35)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    clang = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe"
    sysroot = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/sysroot"
    if not clang.is_file():
        raise SystemExit(f"clang not found at {clang}")

    partitions = sorted((args.catalog / "defs").glob("*.inc"))
    if not partitions:
        raise SystemExit(f"no generated partitions under {args.catalog / 'defs'}")

    totals = {"constants": 0, "structs": 0, "fields": 0}
    cxx_headers: list[str] = []
    with tempfile.TemporaryDirectory(prefix="android-constants-") as directory:
        work = Path(directory)
        for model, target in TARGETS.items():
            total_lines = 0
            for partition in partitions:
                header, constants, layouts = load(partition)
                source = work / f"{partition.stem}-{model}.c"
                source.write_text(render(header, constants, layouts, model), encoding="utf-8", newline="\n")
                base = [str(clang), f"--target={target.format(api=args.api)}",
                        f"--sysroot={sysroot}", "-fsyntax-only"]
                result = subprocess.run(base + ["-std=c11", str(source)],
                                        capture_output=True, text=True, errors="replace")
                if result.returncode != 0:
                    text = result.stdout + result.stderr
                    if "static assertion" not in text:
                        # A few platform headers spell C++ references outside any
                        # `__cplusplus` guard, so they only compile as C++. The
                        # language flag has to precede the input file.
                        retry = subprocess.run(base + ["-x", "c++", "-std=c++17", str(source)],
                                               capture_output=True, text=True, errors="replace")
                        if retry.returncode == 0:
                            cxx_headers.append(header)
                            print(f"note: {header} is only valid as C++; checked under C++")
                            result = retry
                if result.returncode != 0:
                    detail = (result.stdout + result.stderr).strip().splitlines()
                    print(f"FAIL: {header} does not agree with clang for the {model}-bit model")
                    for line in detail[:12]:
                        print("   ", line)
                    return 1
                total_lines += len(constants) + sum(
                    1 + len(row.get("fields", {})) for row in layouts)
                if model == "64":
                    totals["constants"] += len(constants)
                    totals["structs"] += len(layouts)
                    totals["fields"] += sum(len(row.get("fields", {})) for row in layouts)
            print(f"PASS: {len(partitions)} partitions, {total_lines} assertions compile for the "
                  f"{model}-bit model ({target.format(api=args.api)})")
            if args.verbose:
                for partition in partitions:
                    header, constants, layouts = load(partition)
                    print(f"      {header:32} constants={len(constants):4} structs={len(layouts):3}")
    print(f"PASS: {totals['constants']} constants, {totals['structs']} structures and "
          f"{totals['fields']} offsets agree with the NDK headers on both data models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
