#!/usr/bin/env python3
"""Extract runnable tutorial fixtures from the XIRASM documentation.

The documentation is the source of truth for the tutorial examples.  This tool
turns the annotated examples inside a document into assembler fixtures under
``tests/tutorial/`` and records them in ``tests/tutorial/manifest.tsv`` so that
``zig build test`` assembles them exactly as the manual claims.

Annotation
----------

An example becomes a fixture only when its fence carries an ``id``::

    ```asm id=hello target=x86-64 bytes=b82a000000c3
    x86.use64()

    const answer: u32 = 40 + 2

    entry:
        mov eax, answer
        ret
    ```

Supported info-string keys:

``id``      Fixture name.  ``[A-Za-z0-9._-]+``, unique within the document.
``target``  CLI ISA name (``x86-64``, ``rv64``, ``aarch64``, ...).
            Defaults to ``x86-64``.
``bytes``   Expected output bytes, hex, no separators.  Overrides derivation.
``error``   Expected diagnostic substring.  Overrides derivation.
``skip``    Keep the ``id`` for cross-referencing but emit no fixture.

When ``bytes`` and ``error`` are absent, the expectation is derived from the
next fenced block in the document; prose in between is allowed:

* a ``text`` block whose first line is ``bytes: ...`` or ``error: ...``;
* a ``text`` block that consists entirely of hex byte pairs, which is the byte
  dump style the manual already uses for expected output;
* otherwise the example is asserted only to assemble successfully (``ok``).

Line endings
------------

The repository sets ``core.autocrlf=true`` while ``.gitattributes`` declares
``*.md text eol=lf``, so one checkout holds CRLF and another LF while both
report a clean ``git status``.  Every document is therefore normalised to LF
before hashing, and every fixture is written with LF, which keeps ``sha256``
stable across checkouts.

Usage
-----

::

    python tools/doc_examples.py extract --doc document/language.md
    python tools/doc_examples.py check
    python tools/doc_examples.py list --doc document/language.md
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = "tests/tutorial/manifest.tsv"
DEFAULT_ZIG = "tests/tutorial/manifest.zig"
FIXTURE_ROOT = "tests/tutorial"
FORMAT_FIXTURE_DIR = "format"
DOC_ROOT = "document"

FENCE_RE = re.compile(r"^ {0,3}```(.*)$")
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
FIXTURE_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
HEX_PAIR_RE = re.compile(r"^[0-9a-fA-F]{2}$")
BYTES_SPEC_RE = re.compile(r"^bytes\s*:\s*(.*)$", re.IGNORECASE)
ERROR_SPEC_RE = re.compile(r"error\s*:\s*(.+)$", re.IGNORECASE)

SOURCE_LANGS = frozenset({"xir", "asm", "xiras"})
OUTPUT_LANGS = frozenset({"text", "txt"})
LOOKAHEAD_LINES = 25

MANIFEST_COLUMNS = (
    "id",
    "doc",
    "block",
    "section",
    "source",
    "target",
    "case",
    "expected",
    "sha256",
)


class DocError(Exception):
    """A document the pipeline cannot consume."""


# --------------------------------------------------------------------------- #
# Document parsing
# --------------------------------------------------------------------------- #


@dataclass
class Fence:
    index: int
    info: str
    lang: str
    meta: dict[str, str]
    flags: set[str]
    lines: list[str]
    start_line: int
    end_line: int
    section: str = ""


@dataclass
class Fixture:
    id: str
    doc: str
    block: int
    section: str
    source: str
    target: str
    expected: str
    text: str
    sha256: str = field(default="")

    @property
    def case(self) -> str:
        return "negative" if self.expected.startswith("error:") else "positive"


def read_document(path: Path) -> str:
    text = path.read_bytes().decode("utf-8")
    if text.startswith("\ufeff"):
        text = text[1:]
    # Normalise so a CRLF checkout and an LF checkout hash identically.
    return text.replace("\r\n", "\n").replace("\r", "\n")


def parse_info_string(info: str) -> tuple[str, dict[str, str], set[str]]:
    """Split a fence info string into language, ``key=value`` pairs and flags."""
    tokens: list[str] = []
    token = ""
    in_quotes = False
    for char in info.strip():
        if char == '"':
            in_quotes = not in_quotes
            token += char
            continue
        if char.isspace() and not in_quotes:
            if token:
                tokens.append(token)
            token = ""
            continue
        token += char
    if token:
        tokens.append(token)

    lang = ""
    meta: dict[str, str] = {}
    flags: set[str] = set()
    for position, item in enumerate(tokens):
        if position == 0 and "=" not in item:
            lang = item.lower()
            continue
        if "=" not in item:
            flags.add(item)
            continue
        key, _, value = item.partition("=")
        meta[key.strip().lower()] = value.strip().strip('"')
    return lang, meta, flags


def section_for(headings: list[tuple[int, str]], line: int) -> str:
    current = ""
    for heading_line, heading_text in headings:
        if heading_line < line:
            current = heading_text
        else:
            break
    return current


def parse_fences(text: str) -> list[Fence]:
    """Return every fenced block in document order."""
    lines = text.split("\n")
    headings = [
        (number, match.group(2).strip())
        for number, line in enumerate(lines, start=1)
        for match in [HEADING_RE.match(line)]
        if match
    ]

    fences: list[Fence] = []
    current: Fence | None = None
    for number, line in enumerate(lines, start=1):
        match = FENCE_RE.match(line)
        if current is None:
            if match is None:
                continue
            lang, meta, flags = parse_info_string(match.group(1))
            current = Fence(
                index=len(fences) + 1,
                info=match.group(1).strip(),
                lang=lang,
                meta=meta,
                flags=flags,
                lines=[],
                start_line=number,
                end_line=number,
                section=section_for(headings, number),
            )
            continue
        if match is not None:
            current.end_line = number
            fences.append(current)
            current = None
            continue
        current.lines.append(line)
    if current is not None:
        current.end_line = len(lines)
        fences.append(current)
    return fences


def normalise_hex(raw: str) -> str:
    compact = re.sub(r"[^0-9a-fA-F]", "", raw)
    if not compact:
        raise DocError("expected output has no hexadecimal bytes in %r" % raw)
    if len(compact) % 2 != 0:
        raise DocError("expected output has an odd number of hex digits in %r" % raw)
    return compact.lower()


def expected_from_output_block(fence: Fence) -> str | None:
    """Interpret a ``text`` block that follows an example as its expectation."""
    filled = [line.strip() for line in fence.lines if line.strip()]
    if not filled:
        return None

    match = BYTES_SPEC_RE.match(filled[0])
    if match:
        return "bytes:" + normalise_hex(match.group(1))

    match = ERROR_SPEC_RE.search(filled[0])
    if match:
        needle = match.group(1).strip()
        if not needle:
            raise DocError("error expectation on line %d is empty" % fence.start_line)
        return "error:" + needle

    if all(HEX_PAIR_RE.match(token) for line in filled for token in line.split()):
        joined = "".join(token.lower() for line in filled for token in line.split())
        return "bytes:" + joined
    return None


def fixture_text(fence: Fence) -> str:
    lines = list(fence.lines)
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        raise DocError("example on line %d is empty" % fence.start_line)
    return "\n".join(lines) + "\n"


def sha256_of(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def fixture_relpath(doc: str, fixture_id: str, negative: bool) -> str:
    try:
        relative = Path(doc).relative_to(DOC_ROOT)
    except ValueError as error:
        raise DocError("%s is not under %s/" % (doc, DOC_ROOT)) from error
    directory = Path(FIXTURE_ROOT) / relative.with_suffix("")
    if negative:
        directory = directory / "negative"
    return (directory / (fixture_id + ".xir")).as_posix()


def expected_for(fences: list[Fence], position: int, fence: Fence) -> str:
    """The expectation for one example: declared, derived, or `ok`."""
    if "bytes" in fence.meta:
        return "bytes:" + normalise_hex(fence.meta["bytes"])
    if "error" in fence.meta:
        return "error:" + fence.meta["error"]
    following = fences[position + 1] if position + 1 < len(fences) else None
    if (
        following is not None
        and following.lang in OUTPUT_LANGS
        and following.start_line - fence.end_line <= LOOKAHEAD_LINES
    ):
        derived = expected_from_output_block(following)
        if derived is not None:
            return derived
    return "ok"


def collect_fixtures(doc: str) -> list[Fixture]:
    """Return every annotated example in ``doc``, in document order."""
    path = REPO_ROOT / doc
    if not path.is_file():
        raise DocError("document not found: %s" % doc)
    fences = parse_fences(read_document(path))

    fixtures: list[Fixture] = []
    seen: dict[str, int] = {}
    for position, fence in enumerate(fences):
        if "id" not in fence.meta:
            continue
        if fence.lang not in SOURCE_LANGS:
            raise DocError(
                "example %s on line %d declares no source language; use one of %s"
                % (fence.meta["id"], fence.start_line, ", ".join(sorted(SOURCE_LANGS)))
            )
        fixture_id = fence.meta["id"]
        if not FIXTURE_ID_RE.match(fixture_id):
            raise DocError("invalid fixture id %r on line %d" % (fixture_id, fence.start_line))
        if fixture_id in seen:
            raise DocError(
                "duplicate fixture id %r (lines %d and %d)"
                % (fixture_id, seen[fixture_id], fence.start_line)
            )
        seen[fixture_id] = fence.start_line
        if "skip" in fence.flags:
            continue

        expected = expected_for(fences, position, fence)
        text = fixture_text(fence)
        fixtures.append(
            Fixture(
                id=fixture_id,
                doc=doc,
                block=fence.index,
                section=fence.section,
                source=fixture_relpath(doc, fixture_id, expected.startswith("error:")),
                target=fence.meta.get("target", "x86-64"),
                expected=expected,
                text=text,
                sha256=sha256_of(text),
            )
        )
    return fixtures


# --------------------------------------------------------------------------- #
# Manifest
# --------------------------------------------------------------------------- #


def load_manifest(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    rows: list[dict[str, str]] = []
    header: list[str] | None = None
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    for number, line in enumerate(text.split("\n"), start=1):
        if not line.strip():
            continue
        cells = line.split("\t")
        if header is None:
            header = [cell.strip() for cell in cells]
            if header != list(MANIFEST_COLUMNS):
                raise DocError(
                    "%s: unexpected header %s, expected %s"
                    % (path, header, list(MANIFEST_COLUMNS))
                )
            continue
        if len(cells) != len(header):
            raise DocError("%s:%d: expected %d columns" % (path, number, len(header)))
        rows.append(dict(zip(header, cells)))
    return rows


def manifest_row(fixture: Fixture) -> dict[str, str]:
    return {
        "id": fixture.id,
        "doc": fixture.doc,
        "block": str(fixture.block),
        "section": fixture.section.replace("\t", " "),
        "source": fixture.source,
        "target": fixture.target,
        "case": fixture.case,
        "expected": fixture.expected,
        "sha256": fixture.sha256,
    }


def write_manifest(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["\t".join(MANIFEST_COLUMNS)]
    for row in rows:
        lines.append("\t".join(row.get(column, "") for column in MANIFEST_COLUMNS))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def render_zig(rows: list[dict[str, str]]) -> str:
    """Render the manifest as the module `build.zig` imports.

    The build runner caches the configured step graph, so a manifest that was
    only read at configure time could go stale without notice.  Importing a
    generated module makes the fixture list a real build-script dependency.
    """
    out = [
        "// Generated by tools/doc_examples.py from the XIRASM manual.",
        "// Do not edit by hand; run `python tools/doc_examples.py extract --doc <doc>`.",
        "",
        "pub const Fixture = struct {",
        "    id: []const u8,",
        "    source: []const u8,",
        "    target: []const u8,",
        "    expected: []const u8,",
        "};",
        "",
        "pub const fixtures = [_]Fixture{",
    ]
    for row in rows:
        out.append("    .{")
        for key, value in (
            ("id", row["id"]),
            ("source", row["source"]),
            ("target", row["target"]),
            ("expected", row["expected"]),
        ):
            out.append('        .%s = "%s",' % (key, value.replace("\\", "\\\\").replace('"', '\\"')))
        out.append("    },")
    out.append("};")
    return "\n".join(out) + "\n"


def write_zig(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_zig(rows), encoding="utf-8", newline="\n")


def ordered_docs(rows: list[dict[str, str]]) -> list[str]:
    docs: list[str] = []
    for row in rows:
        if row["doc"] not in docs:
            docs.append(row["doc"])
    return docs


# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #


def command_extract(args: argparse.Namespace) -> int:
    if not args.doc:
        raise DocError("extract needs at least one --doc")
    path = REPO_ROOT / args.manifest
    existing = load_manifest(path)
    by_doc: dict[str, list[dict[str, str]]] = {}
    for row in existing:
        by_doc.setdefault(row["doc"], []).append(row)

    requested = list(dict.fromkeys(args.doc))
    docs = ordered_docs(existing)
    for doc in requested:
        if doc not in docs:
            docs.append(doc)

    status = 0
    for doc in requested:
        try:
            fixtures = collect_fixtures(doc)
        except DocError as error:
            print("error: %s: %s" % (doc, error), file=sys.stderr)
            status = 1
            continue
        rows: list[dict[str, str]] = []
        for fixture in fixtures:
            target_path = REPO_ROOT / fixture.source
            target_path.parent.mkdir(parents=True, exist_ok=True)
            target_path.write_bytes(fixture.text.encode("utf-8"))
            rows.append(manifest_row(fixture))
        by_doc[doc] = rows
        print("%s: %d fixture(s)" % (doc, len(rows)))

    if status != 0:
        return status

    merged: list[dict[str, str]] = []
    for doc in docs:
        merged.extend(by_doc.get(doc, []))
    write_manifest(path, merged)
    print("manifest: %s (%d rows)" % (path.relative_to(REPO_ROOT).as_posix(), len(merged)))
    write_zig(REPO_ROOT / args.zig, merged)
    print("module:   %s" % Path(args.zig).as_posix())
    return 0


def command_check(args: argparse.Namespace) -> int:
    path = REPO_ROOT / args.manifest
    rows = load_manifest(path)
    errors: list[str] = []
    warnings: list[str] = []

    if len({(row["doc"], row["id"]) for row in rows}) != len(rows):
        errors.append("the manifest repeats a (doc, id) pair")

    by_doc: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_doc.setdefault(row["doc"], []).append(row)

    expected_files: set[str] = set()
    for doc, doc_rows in sorted(by_doc.items()):
        try:
            fixtures = {fixture.id: fixture for fixture in collect_fixtures(doc)}
        except DocError as error:
            errors.append("%s: %s" % (doc, error))
            continue
        for row in doc_rows:
            fixture = fixtures.get(row["id"])
            if fixture is None:
                errors.append(
                    "%s: the manifest lists %s but the document no longer defines it"
                    % (doc, row["id"])
                )
                continue
            if row["source"] != fixture.source:
                errors.append(
                    "%s:%s: fixture moved from %s to %s"
                    % (doc, row["id"], row["source"], fixture.source)
                )
            for column in ("target", "case", "expected"):
                if row[column] != getattr(fixture, column):
                    errors.append(
                        "%s:%s: %s changed from %r to %r"
                        % (doc, row["id"], column, row[column], getattr(fixture, column))
                    )
            if row["sha256"] != fixture.sha256:
                errors.append(
                    "%s:%s: the example changed since the manifest was written; "
                    "run `tools/doc_examples.py extract`" % (doc, row["id"])
                )
            expected_files.add(row["source"])
            disk = REPO_ROOT / row["source"]
            if not disk.is_file():
                errors.append(
                    "%s:%s: the fixture file %s is missing" % (doc, row["id"], row["source"])
                )
                continue
            disk_text = disk.read_bytes().decode("utf-8").replace("\r\n", "\n")
            if sha256_of(disk_text) != fixture.sha256:
                errors.append(
                    "%s:%s: the fixture file %s no longer matches the document"
                    % (doc, row["id"], row["source"])
                )

    fixture_root = REPO_ROOT / FIXTURE_ROOT
    # The format-tutorial fixtures live under `tests/tutorial/format/` and are
    # verified by `tools/doc_format_examples.py`, which reads the structure each
    # chapter claims instead of a byte string. They are not part of this manifest.
    format_root = fixture_root / FORMAT_FIXTURE_DIR
    if fixture_root.is_dir():
        for candidate in sorted(fixture_root.rglob("*.xir")):
            if format_root in candidate.parents:
                continue
            relative = candidate.relative_to(REPO_ROOT).as_posix()
            if relative not in expected_files:
                warnings.append("stale fixture %s is not listed in the manifest" % relative)

    # A translated chapter repeats its examples, so the same id in two documents
    # must declare the same target and the same expected output. When it does
    # not, one of the two copies was edited alone.
    by_id: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_id.setdefault(row["id"], []).append(row)
    for fixture_id, group in sorted(by_id.items()):
        if len(group) < 2:
            continue
        targets = {row["target"] for row in group}
        expected = {row["expected"] for row in group}
        if len(targets) > 1 or len(expected) > 1:
            warnings.append(
                "example %s is declared differently across documents: %s"
                % (
                    fixture_id,
                    ", ".join(
                        "%s -> %s / %s" % (row["doc"], row["target"], row["expected"])
                        for row in group
                    ),
                )
            )

    zig_path = REPO_ROOT / args.zig
    if not zig_path.is_file():
        errors.append("%s is missing; run `tools/doc_examples.py extract`" % args.zig)
    else:
        actual_zig = zig_path.read_bytes().decode("utf-8").replace("\r\n", "\n")
        if actual_zig != render_zig(rows):
            errors.append(
                "%s is out of sync with the manifest; run `tools/doc_examples.py extract`"
                % args.zig
            )

    for message in warnings:
        print("warning: %s" % message, file=sys.stderr)
    for message in errors:
        print("error: %s" % message, file=sys.stderr)
    if errors:
        print("doc_examples: %d error(s)" % len(errors), file=sys.stderr)
        return 1
    if warnings and getattr(args, "strict", False):
        print("doc_examples: strict mode fails on %d warning(s)" % len(warnings), file=sys.stderr)
        return 1
    print("doc_examples: %d fixture(s) match %s" % (len(rows), path.relative_to(REPO_ROOT).as_posix()))
    return 0


def companion_dir(scratch: str, doc: str) -> Path:
    """Directory for one probed block, mirroring the document's fixture path.

    A block that reads a data file resolves it relative to the file the source
    is written to, so the block has to sit where its fixture would: next to the
    companion files checked in for that document.
    """
    try:
        relative = Path(doc).relative_to(DOC_ROOT)
    except ValueError:
        return Path(scratch)
    directory = Path(scratch) / relative.with_suffix("")
    directory.mkdir(parents=True, exist_ok=True)
    checked_in = REPO_ROOT / FIXTURE_ROOT / relative.with_suffix("")
    if checked_in.is_dir():
        for entry in checked_in.rglob("*"):
            if not entry.is_file() or entry.suffix == ".xir":
                continue
            destination = directory / entry.relative_to(checked_in)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(entry.read_bytes())
    return directory


def command_probe(args: argparse.Namespace) -> int:
    """Assemble every source block in a document and report what it does.

    Auditing a chapter means discovering what its examples actually print, and
    that is the same question for an annotated example and for prose that shows
    no expectation at all. This runs them all through the CLI, so a chapter can
    be rewritten against facts instead of against its own prose.
    """
    binary = REPO_ROOT / args.binary
    if not binary.is_file():
        raise DocError("no assembler at %s; build it or pass --binary" % args.binary)

    docs = list(dict.fromkeys(args.doc))
    if not docs:
        raise DocError("probe needs at least one --doc")

    total = 0
    mismatches = 0
    for doc in docs:
        fences = parse_fences(read_document(REPO_ROOT / doc))
        candidates = [
            (position, fence) for position, fence in enumerate(fences) if fence.lang in SOURCE_LANGS
        ]
        print("== %s (%d source block(s))" % (doc, len(candidates)))
        with tempfile.TemporaryDirectory() as scratch:
            for ordinal, (position, fence) in enumerate(candidates, start=1):
                label = fence.meta.get("id") or ("block %d" % ordinal)
                if args.only and str(ordinal) != args.only and fence.meta.get("id") != args.only:
                    continue
                total += 1
                # Block the file sits in a directory that mirrors where its
                # fixture lives, so a source that reads `payload.bin` finds the
                # copy checked in beside the fixture instead of failing with
                # FileNotAvailable.
                block_dir = companion_dir(scratch, doc)
                source = block_dir / "block.xir"
                output = block_dir / "block.bin"
                if output.is_file():
                    output.unlink()
                source.write_bytes(fixture_text(fence).encode("utf-8"))
                target = fence.meta.get("target", args.target)
                completed = subprocess.run(
                    [str(binary), str(source), "-o", str(output), "--isa", target],
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                )

                expected = expected_for(fences, position, fence)
                stderr = completed.stderr or ""
                first_error = re.sub(r"^\S*block\.xir:\d+:\d+: ", "", stderr.strip().split("\n")[0])
                if expected.startswith("error:"):
                    needle = expected[len("error:") :]
                    ok = completed.returncode != 0 and needle in stderr
                    detail = first_error
                elif expected.startswith("bytes:"):
                    actual = output.read_bytes().hex() if output.is_file() else ""
                    wanted = expected[len("bytes:") :]
                    ok = completed.returncode == 0 and actual == wanted
                    detail = "rc=%d bytes:%s" % (completed.returncode, actual or first_error or "-")
                else:
                    ok = completed.returncode == 0
                    if ok:
                        actual = output.read_bytes().hex() if output.is_file() else ""
                        detail = "rc=0 bytes:%s" % (actual or "-")
                    else:
                        detail = first_error

                if not ok:
                    mismatches += 1
                print(
                    "  %-34s line %-5d %s %s%s"
                    % (
                        label,
                        fence.start_line,
                        "ok " if ok else "BAD",
                        detail,
                        "" if ok else "   <-- declared %s" % expected,
                    )
                )
    print("")
    print("probed %d block(s), %d outside their declaration" % (total, mismatches))
    return 0 if mismatches == 0 else 1


def command_list(args: argparse.Namespace) -> int:
    rows = load_manifest(REPO_ROOT / args.manifest)
    docs = list(dict.fromkeys(args.doc)) if args.doc else ordered_docs(rows)
    if not docs:
        print("doc_examples: no documents given and the manifest is empty")
        return 0
    pending: list[str] = []
    total_examples = 0
    total_annotated = 0
    for doc in docs:
        fences = parse_fences(read_document(REPO_ROOT / doc))
        sources = [fence for fence in fences if fence.lang in SOURCE_LANGS]
        annotated = sum(1 for fence in sources if "id" in fence.meta)
        total_examples += len(sources)
        total_annotated += annotated
        percent = (100.0 * annotated / len(sources)) if sources else 0.0
        print("%-44s %4d example(s) %4d annotated %5.0f%%" % (doc, len(sources), annotated, percent))

        for position, fence in enumerate(fences):
            if fence.lang not in SOURCE_LANGS or "id" in fence.meta:
                continue
            following = fences[position + 1] if position + 1 < len(fences) else None
            if (
                following is None
                or following.lang not in OUTPUT_LANGS
                or following.start_line - fence.end_line > LOOKAHEAD_LINES
            ):
                continue
            try:
                derived = expected_from_output_block(following)
            except DocError:
                derived = None
            if derived is not None:
                pending.append(
                    "%s:%d block %d [%s] expects %s"
                    % (doc, fence.start_line, fence.index, fence.section, derived)
                )
    if pending:
        print()
        print("examples followed by an output block but missing an id:")
        for message in pending:
            print("  %s" % message)
    print()
    print(
        "annotated: %d/%d example(s) (%s fixture(s) in the manifest)"
        % (
            total_annotated,
            total_examples,
            len(rows),
        )
    )
    return 0


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="doc_examples.py",
        description="Extract and verify XIRASM tutorial fixtures from the manual.",
    )
    parser.add_argument(
        "--manifest",
        default=DEFAULT_MANIFEST,
        metavar="PATH",
        help="manifest path relative to the repository root (default: %s)" % DEFAULT_MANIFEST,
    )
    parser.add_argument(
        "--zig",
        default=DEFAULT_ZIG,
        metavar="PATH",
        help="generated module imported by build.zig (default: %s)" % DEFAULT_ZIG,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    extract = subparsers.add_parser("extract", help="write fixtures and refresh the manifest")
    extract.add_argument("--doc", action="append", metavar="PATH", help="document (repeatable)")
    extract.set_defaults(func=command_extract)

    check = subparsers.add_parser("check", help="fail when documents and fixtures drift")
    check.add_argument("--strict", action="store_true", help="treat warnings as errors")
    check.set_defaults(func=command_check)

    listing = subparsers.add_parser("list", help="report example coverage per document")
    listing.add_argument("--doc", action="append", metavar="PATH", help="document (repeatable)")
    listing.set_defaults(func=command_list)

    probe = subparsers.add_parser(
        "probe",
        help="assemble every source block in a document and report rc and bytes",
    )
    probe.add_argument("--doc", action="append", metavar="PATH", help="document (repeatable)")
    probe.add_argument(
        "--binary",
        default="zig-out/bin/xirasm.exe",
        metavar="PATH",
        help="assembler to run (default: %(default)s)",
    )
    probe.add_argument(
        "--target",
        default="x86-64",
        metavar="NAME",
        help="ISA for blocks that declare none (default: %(default)s)",
    )
    probe.add_argument("--only", metavar="ID", help="probe one block by id or 1-based position")
    probe.set_defaults(func=command_probe)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if os_is_windows():
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    try:
        return args.func(args)
    except DocError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1


def os_is_windows() -> bool:
    return sys.platform.startswith("win")


if __name__ == "__main__":
    sys.exit(main())
