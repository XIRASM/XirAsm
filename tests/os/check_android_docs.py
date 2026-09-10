#!/usr/bin/env python3
"""Assemble every XIRASM example the Android documentation shows.

Documentation that ships with the include tree has to be true, and the cheapest
way to keep it true is to assemble it. Every ```asm block in the catalog READMEs
and in `document/os-android.md` is a self-contained source, so each one is
assembled with the release binary; a block that stops assembling fails this check.
The two READMEs are also required to show the same number of examples, so the
Chinese and English pages cannot drift apart.

usage:
  python tests/os/check_android_docs.py --xirasm <path to xirasm>
"""
from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "include" / "os" / "android"
BLOCK = re.compile(r"^```asm\n(.*?)^```$", re.MULTILINE | re.DOTALL)

# The catalog READMEs are a pair; the guide stands alone.
PAIR = (CATALOG / "README.md", CATALOG / "README.zh-CN.md")
DOCUMENTS = (*PAIR, ROOT / "document" / "os-android.md")


def blocks(path: Path) -> list[str]:
    return [match.group(1) for match in BLOCK.finditer(path.read_text(encoding="utf-8"))]


def assemble(xirasm: Path, work: Path, document: Path, index: int, source: str) -> None:
    stem = f"{document.stem}-{index}"
    asm = work / f"{stem}.asm"
    asm.write_text(source, encoding="utf-8", newline="\n")
    result = subprocess.run([str(xirasm), str(asm), "-o", str(work / f"{stem}.bin")],
                            capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        detail = (result.stdout + result.stderr).strip().splitlines()
        raise SystemExit(f"{document.name} example {index + 1} does not assemble:\n"
                         + "\n".join(detail[:6]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xirasm", type=Path, default=ROOT / "zig-out/bin/xirasm.exe")
    args = parser.parse_args()
    xirasm = args.xirasm.resolve()

    for document in DOCUMENTS:
        if not document.is_file():
            raise SystemExit(f"missing documentation: {document}")

    english = blocks(PAIR[0])
    chinese = blocks(PAIR[1])
    if len(english) != len(chinese):
        raise SystemExit(f"the catalog READMEs show a different number of examples: "
                         f"{len(english)} English, {len(chinese)} Chinese")
    if not english:
        raise SystemExit("no asm examples found in the catalog README")

    with tempfile.TemporaryDirectory(prefix="android-docs-") as directory:
        work = Path(directory)
        for document in DOCUMENTS:
            source = blocks(document)
            if not source:
                raise SystemExit(f"{document} shows no asm example")
            for index, block in enumerate(source):
                assemble(xirasm, work, document, index, block)
            relative = document.relative_to(ROOT)
            print(f"PASS: {relative} assembles all {len(source)} documented examples")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
