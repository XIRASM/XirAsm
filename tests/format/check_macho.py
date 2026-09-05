"""Assemble Mach-O DSL fixtures and check layout plus LLVM interoperability."""

import argparse
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(*args, failure=None):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", timeout=60)
    output = result.stdout + result.stderr
    if failure is not None:
        assert result.returncode != 0 and failure in output, (args, output)
    else:
        assert result.returncode == 0, (args, output)
    return output


def name16(value):
    return value.split(b"\0", 1)[0].decode("utf-8")


def read_image(path, *, contiguous=True):
    data = path.read_bytes()
    magic, cpu, subtype, kind, count, commands_size, flags, reserved = struct.unpack_from("<8I", data)
    assert magic == 0xFEEDFACF and reserved == 0
    page = {0x100000C: 0x4000, 0x1000007: 0x1000}[cpu]
    commands, segments, sections = {}, [], []
    offset = 32
    for _ in range(count):
        cmd, size = struct.unpack_from("<II", data, offset)
        assert size >= 8 and size % 8 == 0 and offset + size <= 32 + commands_size
        commands.setdefault(cmd, []).append(offset)
        if cmd == 0x19:
            fields = struct.unpack_from("<16s4Q4I", data, offset + 8)
            segname, va, vs, fo, fs, maximum, initial, ns, segflags = fields
            assert size == 72 + 80 * ns and fo + fs <= len(data) and fs <= vs
            segment = dict(name=name16(segname), va=va, vs=vs, fo=fo, fs=fs,
                           maximum=maximum, initial=initial, sections=[])
            segments.append(segment)
            zero_seen = False
            last_end = va
            for index in range(ns):
                row = struct.unpack_from("<16s16s2Q8I", data, offset + 72 + index * 80)
                sn, sg, addr, length, fileoff, align, reloc, nreloc, sf, r1, r2, r3 = row
                zero = sf & 0xFF == 1
                assert align < 64 and addr % (1 << align) == 0
                assert va <= addr <= addr + length <= va + vs and addr >= last_end
                assert reloc + nreloc * 8 <= len(data)
                if zero:
                    assert fileoff == 0
                    zero_seen = True
                else:
                    assert not zero_seen
                    assert fo <= fileoff <= fileoff + length <= fo + fs
                    assert fileoff % (1 << align) == 0
                    assert addr - va == fileoff - fo
                section = dict(name=name16(sn), segment=name16(sg), va=addr,
                               size=length, fo=fileoff, zero=zero, flags=sf)
                segment["sections"].append(section)
                sections.append(section)
                last_end = addr + length
        offset += size
    assert offset == 32 + commands_size <= len(data)
    identities = [(s["segment"], s["name"]) for s in sections]
    assert len(identities) == len(set(identities))
    if segments and kind in (2, 6):
        assert segments[-1]["name"] == "__LINKEDIT"
        assert segments[-1]["fo"] + segments[-1]["fs"] == len(data)
        if contiguous:
            assert segments[-1]["vs"] == segments[-1]["fs"]
        for current, following in zip(segments, segments[1:]):
            assert current["va"] % page == current["fo"] % page == 0
            if contiguous:
                assert current["va"] + current["vs"] == following["va"]
                assert current["fo"] + current["fs"] == following["fo"]
        if kind == 2:
            assert 0xE in commands and 0x80000028 in commands
            entryoff = struct.unpack_from("<Q", data, commands[0x80000028][0] + 8)[0]
            assert any(s["segment"] == "__TEXT" and s["flags"] & 0x80000000
                       and s["fo"] <= entryoff < s["fo"] + s["size"] for s in sections)
        if kind == 6:
            assert 0xD in commands
    return dict(data=data, cpu=cpu, subtype=subtype, kind=kind, flags=flags,
                commands=commands, segments=segments, sections=sections)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembler", required=True, type=Path)
    parser.add_argument("--llvm-bin", type=Path)
    args = parser.parse_args()
    assembler = args.assembler.resolve()

    def tool(name):
        suffix = ".exe" if __import__("os").name == "nt" else ""
        path = args.llvm_bin / (name + suffix) if args.llvm_bin else shutil.which(name)
        assert path and Path(path).is_file(), f"missing LLVM tool: {name}"
        return path

    reader, objdump, clang, linker = map(tool, ("llvm-readobj", "llvm-objdump", "clang", "ld64.lld"))
    with tempfile.TemporaryDirectory(prefix="xirasm-macho-") as tmp:
        work = Path(tmp)
        images = {}
        for source in sorted((ROOT / "tests/format").glob("*macho64*.asm")):
            output = work / (source.stem + ".bin")
            run(assembler, source, "--target", "x64", "-o", output)
            images[source.stem] = output
            try:
                read_image(output)
                run(reader, "--file-headers", "--macho-segment", "--sections", "--symbols", "--relocs", output)
            except AssertionError as error:
                raise AssertionError(f"{source.name}: {error}") from error
        print(f"PASS: {len(images)} Mach-O fixtures and LLVM readers")

        prologue = 'import("format/format.inc");\n'
        code = 'format_section("__text", format_code | format_readable | format_executable)'
        data = 'format_section("__data", format_data | format_readable | format_writeable)'
        bss = 'format_section("__bss", format_uninitialized_data | format_readable | format_writeable)'
        target = 'format_macho64_target_x86_64(0x000e0000, 0x000e0000)'
        text_segment = f'format_macho64_segment("__TEXT", format_load | format_readable | format_executable, list.of({code}))'
        plan = f'let image: map = format_macho64_exe({target}, list.of({text_segment}))\n'
        invalid = [
            ('align-overflow', 'const bad: u64 = macho_align_up(0xffffffffffffffff, 8)', 'Mach-O alignment overflows'),
            ('align-zero', 'const bad: u64 = macho_align_up(1, 0)', 'Mach-O alignment is zero'),
            ('align-non-power', 'const bad: u64 = macho_align_up(1, 3)', 'Mach-O alignment is not a power'),
            ('version-overflow', 'const bad: map = format_macho64_target_x86_64(1, 0x100000000)', 'Mach-O version exceeds'),
            ('object-zerofill-order', f'const bad: map = format_macho64_object({target}, list.of({bss}, {data}))', 'Mach-O zerofill sections must be last'),
            ('duplicate-section', f'const bad: map = format_macho64_object({target}, list.of({code}, {code}))', 'Mach-O section name is duplicated'),
            ('end-without-begin', plan + 'format_begin(image); format_section_end(image, "__text");', 'lowering failed'),
            ('nested-section', plan + 'format_begin(image); format_section_begin(image, "__text"); format_section_begin(image, "__text");', 'lowering failed'),
            ('unclosed-section', plan + 'format_begin(image); format_section_begin(image, "__text"); format_finish(image);', 'lowering failed'),
            ('section-u32-offset', 'macho_section64("a", "b", 0, 1, 0x100000000, 0, 0, 0, 0, 0, 0, 0);', 'InvalidApiInteger'),
        ]
        duplicate = (ROOT / 'tests/format/format_macho64_arm64_duplicate_sections.asm').read_text()
        ambiguous = duplicate.replace('import("../../include/format/format.inc");', prologue)
        ambiguous = ambiguous.replace('format_macho64_section_begin(image, "__TEXT", "common")', 'format_section_begin(image, "common")')
        invalid.append(('ambiguous-section', ambiguous, 'Mach-O section name is ambiguous'))
        for name, body, diagnostic in invalid:
            source = work / (name + '.asm')
            source.write_text(prologue + body, encoding='utf-8')
            run(assembler, source, '-o', work / (name + '.bin'), failure=diagnostic)
        print(f"PASS: {len(invalid)} invalid plans fail with expected diagnostics")

        for arch in ('arm64', 'x86_64'):
            asm = '.text\n.globl _main, _callee\n_main:\n_callee:\nret\n.data\n.globl _data\n_data:\n.quad 42\n'
            source = work / (arch + '.s')
            source.write_text(asm, encoding='utf-8')
            obj = work / (arch + '.o')
            run(clang, '-target', arch + '-apple-macos14', '-c', source, '-o', obj)
            assert read_image(obj)['subtype'] == (0 if arch == 'arm64' else 3)
            for kind, option in (('exe', []), ('dylib', ['-dylib'])):
                linked = work / f'reference-{arch}-{kind}'
                run(linker, '-arch', arch, '-platform_version', 'macos', '14.0', '14.0',
                    '-no_adhoc_codesign', *option, obj, '-o', linked)
                parsed = read_image(linked)
                assert parsed['subtype'] == (0 if arch == 'arm64' else 0x80000003 if kind == 'exe' else 3)
            linked = work / (arch + '-relocations')
            run(linker, '-arch', arch, '-platform_version', 'macos', '14.0', '14.0',
                '-no_adhoc_codesign', '-e', '_start', images[f'macho64_{arch}_obj'], obj, '-o', linked)
            run(reader, '--file-headers', '--sections', linked)
            dylib = images[f'macho64_{arch}_dylib_exports']
            exports = run(objdump, '--macho', '--exports-trie', dylib)
            for name in (('_entry', '_answer') if arch == 'arm64' else ('_add7', '_sub3')):
                assert name in exports
            linked = work / (arch + '-dylib-consumer')
            run(linker, '-arch', arch, '-platform_version', 'macos', '14.0', '14.0',
                '-no_adhoc_codesign', obj, dylib, '-o', linked)
            imports = run(objdump, '--macho', '--bind', '--indirect-symbols', images[f'macho64_{arch}_exe_import'])
            expected = ('_entry', '_answer') if arch == 'arm64' else ('_add7', '_sub3')
            assert all(name in imports for name in expected) and '__got' in imports
        print('PASS: Clang/LLD target headers, object relocations, dylib exports and import metadata')


if __name__ == '__main__':
    main()
