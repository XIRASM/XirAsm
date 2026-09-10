# Android platform symbol catalog

The tables in this directory are derived from the stub libraries that ship with
the Android NDK, release r27d
(`Pkg.Revision = 27.3.13750724`), which are distributed by the
Android Open Source Project under the Apache License, Version 2.0.

What is derived: symbol names, the stub library that provides them, the first API
level in which each appears, the GNU version tag the stub declares, and the ABIs
that export them. The generator is `generate_android_symbols.py` in the XIRASM repository, and
`manifest.json` records the counts and a digest of the exact stub files used.

The stub libraries are link-time descriptions of the platform surface. They do
not enumerate everything a device may resolve at run time, so a symbol that is
absent here is not proof that no device provides it, and a few stub entries are
internals the platform libraries keep private. `README.md` describes both sides
of that boundary and names the tools that check a target device.
