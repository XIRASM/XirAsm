# XIRASM IO Test Suite

This directory is the dedicated test root for the XIRASM runtime IO library.

It is intentionally separate from the existing repository `tests/` tree.
The existing tree belongs to compiler, frontend, format, API-matrix, and
integration workstreams and must not receive IO-library fixtures.

## Why `test/io/`

The test path mirrors the published package:

```text
include/io/  <->  test/io/
```

The portable IO facade is a first-class library domain. It is not a child of
the raw operating-system API layer, so its tests do not belong under
`test/os/io/`.

Future raw platform-library tests may use:

```text
test/os/linux/
test/os/windows/
```

Those tests will validate syscall tables, ABI helpers, Win32 declarations, and
other OS-specific surfaces independently from the portable IO contract.

## Planned Layout

```text
test/io/
├─ contract/       # shared portable-contract fixtures
├─ abi/            # ABI boundary and register/stack probes
├─ file/           # file-operation fixtures
├─ console/        # standard IO and console fixtures
├─ stream/         # sequential/buffered IO fixtures
├─ path/           # path and encoding fixtures
├─ map/            # file-mapping fixtures
└─ data/           # deterministic input and expected-output data
```

Create subdirectories only when their first real fixture is added.

Platform and width belong in fixture names:

```text
test/io/file/linux64-core.asm
test/io/file/windows64-core.asm
```

## Rules

- Test XIRASM `.inc` libraries with XIRASM `.asm` sources.
- Do not add Zig test implementations for this workstream.
- Do not modify `build.zig` to register IO tests.
- Use existing documented XIRASM command entry points.
- Keep Linux and Windows runtime execution separate.
- Run Windows fixtures natively and Linux fixtures under WSL.
- Reuse the same contract scenario on both platforms when semantics are meant
  to match.
- Review every generated binary with static tools before runtime execution.
- Keep raw OS API tests out of this directory.
- Do not place IO fixtures under the existing `tests/` tree.
