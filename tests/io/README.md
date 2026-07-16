# XIRASM IO Test Suite

This directory contains the XIRASM runtime IO library fixtures under the
repository's single `tests/` root. The IO library is experimental, but its
fixtures follow the same repository-level ownership as compiler, frontend,
format, API, and integration tests.

## Why `tests/io/`

The test path mirrors the published package:

```text
include/io/  <->  tests/io/
```

The portable IO facade is a first-class library domain. It is not a child of
the raw operating-system API layer, so its tests do not belong under
`test/os/io/`.

Future raw platform-library tests may use:

```text
tests/os/linux/
tests/os/windows/
```

Those tests will validate syscall tables, ABI helpers, Win32 declarations, and
other OS-specific surfaces independently from the portable IO contract.

## Planned Layout

```text
tests/io/
├─ contract/       # shared portable-contract fixtures
├─ abi/            # ABI boundary and register/stack probes
├─ file/           # file-operation fixtures
├─ console/        # standard IO and console fixtures
├─ stream/         # sequential/buffered IO fixtures
├─ path/           # path and encoding fixtures
├─ map/            # file-mapping fixtures
├─ optimization/   # ABI sentinels and native x86-64 measurement fixtures
└─ data/           # deterministic input and expected-output data
```

Create subdirectories only when their first real fixture is added.

Platform and width belong in fixture names:

```text
tests/io/file/linux64-core.asm
tests/io/file/windows64-core.asm
```

## Rules

- Test XIRASM `.inc` libraries with XIRASM `.asm` sources.
- Do not add Zig test implementations for this workstream.
- Use existing documented XIRASM command entry points.
- Keep Linux and Windows runtime execution separate.
- Run Windows fixtures natively and Linux fixtures under WSL.
- Reuse the same contract scenario on both platforms when semantics are meant
  to match.
- Review every generated binary with static tools before runtime execution.
- Keep optimization fixtures deterministic for correctness and ABI checks;
  collect timing on native hardware instead of enforcing noisy cycle thresholds.
- Keep raw OS API tests out of this directory.
- Register deterministic compile-time or byte-level checks in the repository
  build when they can run on every supported development host. Keep native
  runtime execution behind explicit platform-specific gates.
