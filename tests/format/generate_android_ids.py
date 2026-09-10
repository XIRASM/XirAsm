#!/usr/bin/env python3
"""Generate the Android framework resource ID catalog as an XIRASM include.

A manifest or a resource value that references `@android:...` has to carry the
framework's own resource ID, which is `0x01 <type> <entry>`. The platform jar
holds that table in its `resources.arsc`; this tool reads it through `aapt2`,
the platform's own reader, so the catalog comes from the platform rather than
from a second parser of the same bytes.

The generated include builds one map per type, on first use, so importing it
costs nothing and a program that resolves one ID pays for that type alone.

usage:
  python tests/format/generate_android_ids.py \
      --jar %LOCALAPPDATA%/Android/Sdk/platforms/android-37.0/android.jar \
      --aapt2 %LOCALAPPDATA%/Android/Sdk/build-tools/36.0.0/aapt2.exe \
      --emit include/format/android/generated/framework_ids.inc --report
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

PACKAGE_LINE = re.compile(r"^Package name=(\S+) id=(\w+)$")
RESOURCE_LINE = re.compile(r"^    resource (0x[0-9a-fA-F]+) ([^/]+)/(\S+)")


def dump(aapt2: Path, jar: Path) -> list[str]:
    """The platform reader's own view of the jar's resource table."""
    result = subprocess.run([str(aapt2), "dump", "resources", str(jar)],
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    if result.returncode != 0:
        raise SystemExit(f"aapt2 dump failed: {result.stderr.strip()[:400]}")
    return [line for line in result.stdout.splitlines() if not line.startswith("warn:")]


def parse(lines: list[str], package_name: str = "android", public_only: bool = True) -> tuple[dict[str, dict[str, int]], set[str], int]:
    """Return the mapping, the packages seen, and how many entries were skipped.

    Two kinds of entries are left out. Runtime-resource types carry an id above
    0x7f, which the platform numbers dynamically and an application cannot
    reference. Private resources are not part of the stable surface either, and
    the platform marks the public ones, so the catalog keeps those by default.
    """
    table: dict[str, dict[str, int]] = {}
    packages: set[str] = set()
    skipped = 0
    in_package = False
    for line in lines:
        match = PACKAGE_LINE.match(line)
        if match:
            name, package_id = match.group(1), match.group(2)
            packages.add(f"{name}={package_id}")
            in_package = name == package_name
            continue
        if not in_package:
            continue
        resource = RESOURCE_LINE.match(line)
        if not resource:
            continue
        value = int(resource.group(1), 16)
        type_name = resource.group(2)
        entry_name = resource.group(3)
        if ((value >> 16) & 0xFF) >= 0x80:
            skipped += 1
            continue
        if public_only and " PUBLIC" not in line:
            skipped += 1
            continue
        bucket = table.setdefault(type_name, {})
        existing = bucket.get(entry_name)
        if existing is not None and existing != value:
            raise SystemExit(f"conflicting id for {type_name}/{entry_name}: {existing:#010x} vs {value:#010x}")
        bucket[entry_name] = value
    return table, packages, skipped


def symbol(type_name: str) -> str:
    """A type name as part of an identifier: `attr-private` becomes `attr_private`."""
    return "_".join(filter(None, "".join(byte if byte.isalnum() else "_" for byte in type_name).split("_")))


def escape_key(name: str) -> str:
    """A resource name as a flat TOML key.

    Framework names contain dots (`Theme.DeviceDefault`), which TOML reads as a
    path into nested tables, and this parser's table reader follows that even for
    quoted keys. The catalog therefore stores names flat, with dots turned into a
    character no Android resource name contains, and lookups undo it.
    """
    if "~" in name:
        raise SystemExit(f"resource name already contains the escape character: {name}")
    return name.replace(".", "~")


def table_name(type_name: str) -> str:
    """A type name as a TOML table key and as part of an identifier.

    `attr-private` has a character a bare TOML key cannot carry, and the same
    spelling names the per-type helper, so both use underscores.
    """
    return re.sub(r"[^A-Za-z0-9_]", "_", type_name)


def render_toml(table: dict[str, dict[str, int]], platform: str) -> str:
    total = sum(len(entries) for entries in table.values())
    lines = [
        "# Android framework resource IDs.",
        "#",
        f"# Generated from the platform jar ({platform}) through aapt2, the platform's",
        "# own reader. Do not edit by hand; regenerate with",
        "# tests/format/generate_android_ids.py.",
        "#",
        f"# {len(table)} tables, {total} entries. Dots inside a resource name are",
        "# written as '~' so a name stays one key; android_id turns them back.",
        "",
    ]
    for type_name in sorted(table):
        entries = table[type_name]
        lines.append(f"[{table_name(type_name)}]")
        for entry_name in sorted(entries):
            lines.append(f'"{escape_key(entry_name)}" = {entries[entry_name]:#010x}')
        lines.append("")
    return "\n".join(lines)


def render_include(table: dict[str, dict[str, int]], platform: str) -> str:
    total = sum(len(entries) for entries in table.values())
    types = sorted(table)
    lines = [
        "// Android framework resource IDs.",
        "//",
        f"// The table itself is the data file beside this include, generated from the",
        f"// platform jar ({platform}) through aapt2. Reading it is one native TOML",
        "// parse, so importing this file costs nothing and a program pays for the",
        f"// table only when it asks for it: {len(types)} types, {total} entries.",
        "//",
        "//   const ids: map = android_framework_ids()",
        "//   app = apk_use_theme_id(app, android_style_id(ids, \"Theme.DeviceDefault\"));",
        "//",
        "// Load the table once and pass it to the lookups: each lookup is then a map",
        "// read rather than another parse.",
        "",
        "const android_framework_data: string = \"format/android/generated/framework_ids.toml\"",
        "",
        "fn android_framework_ids() -> map {",
        "    return toml.file(android_framework_data)",
        "}",
        "",
        "// Resource names carry dots (`Theme.DeviceDefault`); the table stores them",
        "// flat with '~' in place of the dot.",
        "fn android_key(name: string) -> string {",
        "    return replace(name, \".\", \"~\")",
        "}",
        "",
        "fn android_id(ids: map, type_name: string, entry_name: string) -> u64 {",
        "    assert(map.has(ids, type_name), \"android framework resource type is unknown\");",
        "    const entries: map = map.get(ids, type_name)",
        "    const key: string = android_key(entry_name)",
        "    assert(map.has(entries, key), \"android framework resource name is unknown\");",
        "    return map.get(entries, key)",
        "}",
        "",
    ]
    for type_name in types:
        normalized = table_name(type_name)
        lines.append(f"fn android_{normalized}_id(ids: map, entry_name: string) -> u64 {{")
        lines.append(f'    return android_id(ids, "{normalized}", entry_name)')
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", required=True, type=Path, help="platform android.jar")
    parser.add_argument("--aapt2", required=True, type=Path)
    parser.add_argument("--emit", type=Path)
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--include-private", action="store_true",
                        help="keep private and dynamic entries as well")
    args = parser.parse_args()

    table, packages, skipped = parse(dump(args.aapt2, args.jar), public_only=not args.include_private)
    total = sum(len(entries) for entries in table.values())
    print(f"android package: {len(table)} types, {total} entries")
    print("packages in the jar: " + ", ".join(sorted(packages)))
    print(f"entries skipped (private or dynamic): {skipped}")

    # Two constants this repository verifies independently against a reference
    # manifest have to come back from the platform table unchanged.
    for type_name, entry_name, expected in (("attr", "label", 0x01010001), ("attr", "icon", 0x01010002)):
        actual = table[type_name].get(entry_name)
        if actual != expected:
            raise SystemExit(f"{type_name}/{entry_name} is {actual!r}, expected {expected:#010x}")
    print("cross-check: attr/label and attr/icon match the verified constants")

    if args.report:
        for type_name in sorted(table, key=lambda name: -len(table[name]))[:10]:
            print(f"  {type_name:16s} {len(table[type_name]):6d}")

    if args.emit:
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        platform = args.jar.parent.name
        data_path = args.emit.parent / "framework_ids.toml"
        data_path.write_text(render_toml(table, platform), encoding="utf-8")
        args.emit.write_text(render_include(table, platform), encoding="utf-8")
        print(f"wrote {data_path} ({data_path.stat().st_size} bytes)")
        print(f"wrote {args.emit} ({args.emit.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
