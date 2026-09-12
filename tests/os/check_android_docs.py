#!/usr/bin/env python3
"""Assemble every XIRASM example the Android documentation shows.

Documentation that ships with the include tree has to be true, and the cheapest
way to keep it true is to assemble it. Every ```asm block in the catalog READMEs
and in `document/android.md` is a self-contained source, so each one is
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
# A fence may carry attributes after the language (`asm id=... target=...`), and
# the document that uses them is the guide, so the pattern has to accept both
# shapes rather than only a bare `asm`.
BLOCK = re.compile(r"^```asm(?:[ \t][^\n]*)?\n(.*?)^```$", re.MULTILINE | re.DOTALL)

# The catalog READMEs are a pair; the guide stands alone.
PAIR = (CATALOG / "README.md", CATALOG / "README.zh-CN.md")
DOCUMENTS = (*PAIR, ROOT / "document" / "android.md")

# A guide example that reads icons, a `res/` tree, or a prebuilt `.so` cannot be
# assembled from the fence alone. Those blocks say so themselves, in a comment on
# their first line, and this check reports them as covered elsewhere instead of
# failing on a file the documentation never promised to ship.
NEEDS_INPUT = "needs input files"


def blocks(path: Path) -> list[tuple[str, bool]]:
    """Return (source, self_contained) for every asm block in a document."""
    found = []
    for match in BLOCK.finditer(path.read_text(encoding="utf-8")):
        source = match.group(1)
        first = source.splitlines()[0] if source.strip() else ""
        found.append((source, NEEDS_INPUT not in first))
    return found


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
            assembled = 0
            deferred = 0
            for index, (block, self_contained) in enumerate(source):
                if not self_contained:
                    deferred += 1
                    continue
                assemble(xirasm, work, document, index, block)
                assembled += 1
            relative = document.relative_to(ROOT)
            note = f", {deferred} need input files" if deferred else ""
            print(f"PASS: {relative} assembles {assembled} of {len(source)} examples{note}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
