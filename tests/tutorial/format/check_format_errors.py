#!/usr/bin/env python3
"""Check that a format-tutorial negative fixture reports the error it claims.

A negative example in the guide carries the diagnostic it produces in a
`# expect-error:` comment, and the chapter quotes that same sentence. This
script assembles the fixture and compares the reported message, so a drifting
diagnostic fails the build instead of quietly making the guide wrong.

Usage:

    python tests/tutorial/format/check_format_errors.py <xirasm> <fixture.xir> [<fixture.xir> ...]

`xirasm` is the assembler to run and must be an absolute path, because the
fixtures are passed as build artifacts.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

MARKER = "# expect-error:"


def expected_error(source: Path) -> str | None:
    for line in source.read_text(encoding="utf-8").splitlines():
        if line.startswith(MARKER):
            return line[len(MARKER) :].strip()
    return None


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    assembler = Path(argv[1])
    failures: list[str] = []
    checked = 0

    for argument in argv[2:]:
        source = Path(argument)
        want = expected_error(source)
        if want is None:
            failures.append("%s: no `%s` line" % (source.name, MARKER))
            continue

        result = subprocess.run(
            [str(assembler), str(source), "-o", str(source.with_suffix(".bin")), "--target", "x86-64"],
            capture_output=True,
            text=True,
            errors="replace",
        )
        if result.returncode == 0:
            failures.append("%s: assembled successfully, expected an error" % source.name)
            continue

        reported = [line for line in (result.stdout + result.stderr).splitlines() if "error:" in line]
        if not reported:
            failures.append("%s: failed without an error message" % source.name)
            continue

        message = reported[0].split("error:", 1)[1].strip()
        if want not in message:
            failures.append("%s: reported %r, expected %r" % (source.name, message, want))
            continue
        checked += 1

    for message in failures:
        print("error: %s" % message, file=sys.stderr)
    if failures:
        print("format errors: %d failure(s)" % len(failures), file=sys.stderr)
        return 1
    print("format errors: %d fixture(s) report their claimed diagnostic" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
