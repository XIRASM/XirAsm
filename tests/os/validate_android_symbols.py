#!/usr/bin/env python3
"""Validate the generated Android platform symbol catalog against the NDK.

The generator parses ELF symbol tables directly. This validator does not trust
that code path at all: it re-derives the same facts with ``llvm-nm`` from the
NDK toolchain, in one batch per ABI and API level, and then compares:

  * every (symbol, library) pair the catalog claims,
  * the first API level recorded for each pair,
  * the ABI set recorded for each symbol,
  * the GNU version tag, where the stub declares one,
  * and the counts and structure inside symbols.toml and manifest.json.

usage:
  python tests/os/validate_android_symbols.py --ndk <ndk root>
  python tests/os/validate_android_symbols.py --ndk <ndk root> --catalog include/os/android
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tomllib
from collections import Counter, defaultdict
from pathlib import Path

ABI_ORDER = (
    "aarch64-linux-android",
    "arm-linux-androideabi",
    "i686-linux-android",
    "riscv64-linux-android",
    "x86_64-linux-android",
)
BARE_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
FUNCTION_TYPES = {"T", "W", "i", "I"}


def load_catalog(catalog: Path) -> dict:
    with (catalog / "catalog" / "symbols.toml").open("rb") as stream:
        return tomllib.load(stream)


def check_structure(catalog_root: Path, data: dict, manifest: dict) -> list[str]:
    problems: list[str] = []
    meta = data.get("meta", {})
    symbols = data.get("symbols", {})
    api_min, api_max = meta.get("api_min"), meta.get("api_max")
    if meta.get("schema") != manifest.get("schema"):
        problems.append("symbols.toml and manifest.json disagree on schema")
    for name, row in symbols.items():
        if not BARE_KEY.match(name):
            problems.append(f"symbol key is not a bare key: {name!r}")
        if not isinstance(row, dict):
            problems.append(f"{name}: expected a table of fields")
            continue
        missing = {"lib", "api", "abis", "kind"} - set(row)
        if missing:
            problems.append(f"{name}: missing field(s) {sorted(missing)}")
            continue
        entry_apis = []
        for entry in row["lib"].split(","):
            if ":" not in entry:
                problems.append(f"{name}: library entry {entry} carries no API level")
                continue
            library, entry_api = entry.rsplit(":", 1)
            entry_apis.append(int(entry_api))
            if not library.endswith(".so"):
                problems.append(f"{name}: library {library} does not look like a shared object name")
        if not (api_min <= row["api"] <= api_max):
            problems.append(f"{name}: api {row['api']} outside {api_min}..{api_max}")
        if entry_apis and row["api"] != min(entry_apis):
            problems.append(f"{name}: api {row['api']} is not the minimum of {entry_apis}")
        if not 0 < row["abis"] < (1 << len(ABI_ORDER)):
            problems.append(f"{name}: abi mask {row['abis']} out of range")
        if row["kind"] not in ("func", "ifunc"):
            problems.append(f"{name}: unknown kind {row['kind']}")
        if row["lib"] != ",".join(sorted(row["lib"].split(","))):
            problems.append(f"{name}: library list is not sorted")
    pairs = sum(len(row["lib"].split(",")) for row in symbols.values() if isinstance(row, dict))
    recomputed = {
        "symbols": len(symbols),
        "symbol_library_pairs": pairs,
        "multi_library_symbols": sum(1 for row in symbols.values()
                                     if isinstance(row, dict) and "," in row["lib"]),
        "libraries": len({entry.rsplit(":", 1)[0] for row in symbols.values()
                          if isinstance(row, dict) for entry in row["lib"].split(",")}),
    }
    for key, value in recomputed.items():
        if manifest.get(key) != value:
            problems.append(f"manifest {key} is {manifest.get(key)}, catalog recomputes {value}")
    if not (catalog_root / "catalog" / "manifest.json").is_file():
        problems.append("manifest.json is missing")
    return problems


def is_elf(path: Path) -> bool:
    """NDK directories also hold linker scripts (libc++.so); llvm-nm rejects them."""
    try:
        with path.open("rb") as stream:
            return stream.read(4) == b"\x7fELF"
    except OSError:
        return False


def run_llvm_nm(llvm_nm: Path, files: list[Path]) -> dict[str, list[tuple[str, str]]]:
    """Return {library: [(symbol, version), ...]} for one ABI and API level."""
    if not files:
        return {}
    result = subprocess.run(
        [str(llvm_nm), "-D", "--defined-only", "--format=posix", *[str(f) for f in files]],
        capture_output=True, text=True, errors="replace",
    )
    if result.returncode != 0:
        raise SystemExit(f"llvm-nm failed: {result.stderr.strip()[:400]}")
    found: dict[str, list[tuple[str, str]]] = defaultdict(list)
    current: str | None = None
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.endswith(":"):
            current = Path(line[:-1]).name
            continue
        fields = line.split()
        if len(fields) < 2 or current is None:
            continue
        name, kind = fields[0], fields[1]
        if kind not in FUNCTION_TYPES:
            continue
        version = ""
        if "@@" in name:
            name, version = name.split("@@", 1)
        found[current].append((name, version))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, default=Path("include/os/android"))
    parser.add_argument("--abis", default=",".join(ABI_ORDER))
    parser.add_argument("--api-min", type=int, default=None)
    parser.add_argument("--api-max", type=int, default=None)
    args = parser.parse_args()

    catalog_root = args.catalog
    data = load_catalog(catalog_root)
    manifest = json.loads((catalog_root / "catalog" / "manifest.json").read_text(encoding="utf-8"))
    meta = data.get("meta", {})
    api_min = args.api_min if args.api_min is not None else meta["api_min"]
    api_max = args.api_max if args.api_max is not None else meta["api_max"]
    abis = [item.strip() for item in args.abis.split(",") if item.strip()]

    problems = check_structure(catalog_root, data, manifest)
    if problems:
        print(f"structure problems ({len(problems)}):")
        for line in problems[:40]:
            print(f"  {line}")

    lib_root = args.ndk / "toolchains" / "llvm" / "prebuilt" / "windows-x86_64" / "sysroot" / "usr" / "lib"
    llvm_nm = args.ndk / "toolchains" / "llvm" / "prebuilt" / "windows-x86_64" / "bin" / "llvm-nm.exe"
    if not llvm_nm.is_file():
        raise SystemExit(f"missing llvm-nm: {llvm_nm}")

    # Independent derivation: first API and ABI set per (symbol, library).
    derived: dict[tuple[str, str], dict] = {}
    versions: dict[tuple[str, str], str] = {}
    invocations = 0
    for abi in abis:
        bit = 1 << ABI_ORDER.index(abi)
        for api in range(api_min, api_max + 1):
            api_dir = lib_root / abi / str(api)
            if not api_dir.is_dir():
                continue
            stubs = [f for f in sorted(api_dir.glob("*.so")) if is_elf(f)]
            invocations += 1
            for library, entries in run_llvm_nm(llvm_nm, stubs).items():
                for name, version in entries:
                    key = (name, library)
                    row = derived.get(key)
                    if row is None:
                        derived[key] = {"min_api": api, "abis": bit}
                    else:
                        row["abis"] |= bit
                        if api < row["min_api"]:
                            row["min_api"] = api
                    if version and key not in versions:
                        versions[key] = version

    catalog_rows: dict[tuple[str, str], int] = {}
    catalog_symbol_api: dict[str, int] = {}
    catalog_mask: dict[str, int] = {}
    catalog_version: dict[tuple[str, str], str] = {}
    for name, row in data["symbols"].items():
        catalog_symbol_api[name] = row["api"]
        catalog_mask[name] = row["abis"]
        for entry in row["lib"].split(","):
            library, entry_api = entry.rsplit(":", 1)
            catalog_rows[(name, library)] = int(entry_api)
            if row.get("ver"):
                catalog_version[(name, library)] = row["ver"]

    missing = sorted(set(catalog_rows) - set(derived))
    extra = sorted(set(derived) - set(catalog_rows))
    api_mismatch = sorted(
        key for key in set(catalog_rows) & set(derived)
        if catalog_rows[key] != derived[key]["min_api"]
    )
    derived_symbol_api: dict[str, int] = {}
    for (name, _library), row in derived.items():
        current = derived_symbol_api.get(name)
        if current is None or row["min_api"] < current:
            derived_symbol_api[name] = row["min_api"]
    symbol_api_mismatch = sorted(
        key for key in set(catalog_symbol_api) | set(derived_symbol_api)
        if catalog_symbol_api.get(key, -1) != derived_symbol_api.get(key, -1)
    )
    derived_mask: dict[str, int] = defaultdict(int)
    for (name, _library), row in derived.items():
        derived_mask[name] |= row["abis"]
    mask_mismatch = sorted(
        name for name in set(catalog_mask) | set(derived_mask)
        if catalog_mask.get(name, 0) != derived_mask.get(name, 0)
    )
    version_mismatch = sorted(
        key for key in set(catalog_version) & set(versions)
        if catalog_version[key] != versions[key]
    )

    print(f"llvm-nm invocations : {invocations}")
    print(f"derived rows        : {len(derived)}")
    print(f"catalog rows        : {len(catalog_rows)}")
    print(f"missing in llvm-nm  : {len(missing)}")
    print(f"extra in llvm-nm    : {len(extra)}")
    print(f"pair first-api diff : {len(api_mismatch)}")
    print(f"symbol first-api    : {len(symbol_api_mismatch)}")
    print(f"abi-mask mismatch   : {len(mask_mismatch)}")
    print(f"version mismatch    : {len(version_mismatch)}")
    for label, items in (("missing", missing), ("extra", extra),
                         ("pair-api", api_mismatch), ("symbol-api", symbol_api_mismatch),
                         ("mask", mask_mismatch), ("version", version_mismatch)):
        for item in items[:8]:
            print(f"  {label}: {item}")

    failed = bool(problems or missing or extra or api_mismatch or symbol_api_mismatch
                  or mask_mismatch or version_mismatch)
    print("catalog validated against llvm-nm" if not failed else "catalog validation FAILED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
