#!/usr/bin/env python3
"""Check the format-tutorial fixtures for the structure the guide claims.

The language-guide fixtures assert an exact byte string, which works because
those examples emit a handful of bytes. A PE image is a kilobyte, so asserting
its whole hex dump inside a fence would be unreadable. These checks parse the
fields the chapters actually claim instead: signatures, machine types, section
rows, directory entries, import and export tables, base relocations, and the
checksum.

Where the format defines an algorithm, this checker implements it
independently rather than trusting the file: `pe_checksum` below follows the
PE specification, so `format_pe_checksum` is verified against the definition
and not against itself. Structure expectations were also confirmed with LLVM's
readers:

    llvm-readobj --file-headers --sections --coff-imports --coff-exports <image>
    llvm-readobj --file-headers --program-headers <image>

Usage:

    python tests/tutorial/format/check_format_fixtures.py <image> [<image> ...]

Fixture ids are unique per chapter, but a name can repeat across chapters
(`elf64-minimal`, for example, belongs to chapter 1 and chapter 3), so the
assembled file name carries the chapter: `<chapter>-<id>.bin`.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        FAILURES.append(message)


# --- shared readers ----------------------------------------------------------


def pe_offset(image: bytes) -> int:
    """Return the file offset of the PE signature."""
    return struct.unpack_from("<I", image, 0x3C)[0]


def optional_header(image: bytes) -> int:
    """Return the file offset of the optional header."""
    return pe_offset(image) + 24


def directory(image: bytes, index: int) -> tuple[int, int]:
    """Return (RVA, size) of data directory `index`."""
    base = optional_header(image) + 112
    return struct.unpack_from("<II", image, base + 8 * index)


def dll_characteristics(image: bytes) -> int:
    return struct.unpack_from("<H", image, optional_header(image) + 70)[0]


def sections_of(image: bytes) -> list[tuple[bytes, int, int, int, int]]:
    """Return (name, file_size, virtual_size, virtual_address, raw_pointer)."""
    offset = pe_offset(image)
    count = struct.unpack_from("<H", image, offset + 6)[0]
    table = optional_header(image) + struct.unpack_from("<H", image, offset + 20)[0]
    rows = []
    for index in range(count):
        entry = table + 40 * index
        name = image[entry : entry + 8].rstrip(b"\0")
        virtual_size = struct.unpack_from("<I", image, entry + 8)[0]
        virtual_address = struct.unpack_from("<I", image, entry + 12)[0]
        file_size = struct.unpack_from("<I", image, entry + 16)[0]
        raw_pointer = struct.unpack_from("<I", image, entry + 20)[0]
        rows.append((name, file_size, virtual_size, virtual_address, raw_pointer))
    return rows


def rva_to_offset(image: bytes, rva: int) -> int | None:
    for _name, file_size, virtual_size, virtual_address, raw_pointer in sections_of(image):
        if virtual_address <= rva < virtual_address + max(file_size, virtual_size):
            return raw_pointer + (rva - virtual_address)
    return None


def pe_checksum(image: bytes) -> int:
    """Compute the PE checksum the way the specification defines it.

    The image is summed as a sequence of 16-bit little-endian words with the
    CheckSum field itself treated as zero. A trailing odd byte counts as the
    low half of a final word. The folded sum is added to the file length.
    """
    data = bytearray(image)
    checksum_field = optional_header(image) + 64
    data[checksum_field : checksum_field + 4] = b"\0\0\0\0"

    total = 0
    for index in range(0, len(data) - 1, 2):
        total += data[index] | (data[index + 1] << 8)
        total = (total & 0xFFFF) + (total >> 16)
    if len(data) % 2:
        total += data[-1]
        total = (total & 0xFFFF) + (total >> 16)

    return (total & 0xFFFF) + len(data)


# --- chapter 1: choosing the output kind -------------------------------------


def check_pe64_minimal(image: bytes) -> None:
    check(image[:2] == b"MZ", "pe64-minimal: no MZ signature")
    offset = pe_offset(image)
    check(image[offset : offset + 4] == b"PE\0\0", "pe64-minimal: no PE signature")
    machine = struct.unpack_from("<H", image, offset + 4)[0]
    check(machine == 0x8664, "pe64-minimal: machine is 0x%04x, expected 0x8664" % machine)

    optional_magic = struct.unpack_from("<H", image, offset + 24)[0]
    check(optional_magic == 0x20B, "pe64-minimal: optional magic 0x%X, expected 0x20B" % optional_magic)

    entry = struct.unpack_from("<I", image, offset + 40)[0]
    check(entry == 0x1000, "pe64-minimal: entry RVA is 0x%X, expected 0x1000" % entry)

    header_size = struct.unpack_from("<I", image, offset + 0x54)[0]
    check(header_size == 512, "pe64-minimal: SizeOfHeaders is %d, expected 512" % header_size)

    subsystem = struct.unpack_from("<H", image, optional_header(image) + 68)[0]
    check(subsystem == 3, "pe64-minimal: subsystem is %d, expected 3" % subsystem)

    characteristics = dll_characteristics(image)
    check(characteristics & 0x100, "pe64-minimal: NX_COMPAT is not set")
    check(not (characteristics & 0x40), "pe64-minimal: DYNAMIC_BASE is set although ASLR is disabled")

    rows = sections_of(image)
    check(len(rows) == 2, "pe64-minimal: %d sections, expected 2" % len(rows))
    if len(rows) == 2:
        check(rows[0][0] == b".text", "pe64-minimal: first section is %r" % rows[0][0])
        check(rows[1][0] == b".bss", "pe64-minimal: second section is %r" % rows[1][0])
        check(rows[0][2] == 3, "pe64-minimal: .text virtual size is %d, expected 3" % rows[0][2])
        check(rows[0][1] == 512, "pe64-minimal: .text raw size is %d, expected 512" % rows[0][1])
        check(rows[1][1] == 0, "pe64-minimal: .bss carries %d file bytes" % rows[1][1])
        check(rows[1][2] == 64, "pe64-minimal: .bss virtual size is %d, expected 64" % rows[1][2])


def check_elf64_minimal(image: bytes) -> None:
    check(image[:4] == b"\x7fELF", "elf64-minimal: no ELF magic")
    check(image[4] == 2, "elf64-minimal: class is %d, expected 2 (64-bit)" % image[4])
    check(image[5] == 1, "elf64-minimal: data encoding is %d, expected 1 (little-endian)" % image[5])

    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 2, "elf64-minimal: e_type is %d, expected 2 (ET_EXEC)" % e_type)
    check(e_machine == 62, "elf64-minimal: e_machine is %d, expected 62 (EM_X86_64)" % e_machine)

    entry = struct.unpack_from("<Q", image, 24)[0]
    check(entry != 0, "elf64-minimal: entry is zero")

    header_size, ph_entry_size = struct.unpack_from("<HH", image, 52)
    check(header_size == 64, "elf64-minimal: e_ehsize is %d, expected 64" % header_size)
    ph_count = struct.unpack_from("<H", image, 56)[0]
    check(ph_count == 1, "elf64-minimal: %d program headers, expected 1" % ph_count)

    p_type, p_flags, p_offset, p_vaddr = struct.unpack_from("<IIQQ", image, 64)
    p_filesz, p_memsz, p_align = struct.unpack_from("<QQQ", image, 64 + 32)
    check(p_type == 1, "elf64-minimal: program header type is %d, expected 1 (PT_LOAD)" % p_type)
    check(p_flags == 5, "elf64-minimal: segment flags are %d, expected 5 (R|X)" % p_flags)
    check(p_vaddr == entry, "elf64-minimal: segment address differs from the entry point")
    check(p_filesz == 9, "elf64-minimal: segment file size is %d, expected 9" % p_filesz)
    check(p_memsz == p_filesz, "elf64-minimal: segment memory size differs from its file size")
    check(p_align == 0x1000, "elf64-minimal: segment alignment is 0x%X, expected 0x1000" % p_align)
    check(p_offset % p_align == p_vaddr % p_align, "elf64-minimal: offset and address are not page-congruent")
    check(64 + ph_count * ph_entry_size <= len(image), "elf64-minimal: program header runs past the file end")


# --- chapter 2: Windows PE and DLLs ------------------------------------------


def check_pe64_executable(image: bytes) -> None:
    check(image[:2] == b"MZ", "pe64-executable: no MZ signature")
    offset = pe_offset(image)
    check(image[offset : offset + 4] == b"PE\0\0", "pe64-executable: no PE signature")
    machine = struct.unpack_from("<H", image, offset + 4)[0]
    check(machine == 0x8664, "pe64-executable: machine is 0x%04x, expected 0x8664" % machine)

    # format_pe_exe must set IMAGE_FILE_EXECUTABLE_IMAGE and must not set IMAGE_FILE_DLL.
    characteristics = struct.unpack_from("<H", image, offset + 22)[0]
    check(characteristics & 0x2, "pe64-executable: IMAGE_FILE_EXECUTABLE_IMAGE is not set")
    check(not (characteristics & 0x2000), "pe64-executable: IMAGE_FILE_DLL is set on an executable")

    entry = struct.unpack_from("<I", image, offset + 40)[0]
    check(entry == 0x1000, "pe64-executable: entry RVA is 0x%X, expected 0x1000" % entry)

    optional = optional_header(image)
    # ImageBase is a QWORD at +24, so SectionAlignment and FileAlignment are the
    # two DWORDs at +32 and +36, not at +4 and +36.
    section_align = struct.unpack_from("<I", image, optional + 32)[0]
    file_align = struct.unpack_from("<I", image, optional + 36)[0]
    check(section_align == 4096, "pe64-executable: SectionAlignment is %d, expected 4096" % section_align)
    check(file_align == 512, "pe64-executable: FileAlignment is %d, expected 512" % file_align)
    check(struct.unpack_from("<H", image, optional + 68)[0] == 3, "pe64-executable: subsystem is not Windows CUI")

    # format_pe_nx and format_pe_aslr_disabled touch the same field.
    flags = dll_characteristics(image)
    check(flags & 0x100, "pe64-executable: NX_COMPAT is not set")
    check(not (flags & 0x40), "pe64-executable: DYNAMIC_BASE is set although ASLR is disabled")
    check(directory(image, 5) == (0, 0), "pe64-executable: a relocation directory exists without relocations")

    rows = sections_of(image)
    check([row[0] for row in rows] == [b".text", b".bss"], "pe64-executable: section names are %r" % [r[0] for r in rows])
    if len(rows) == 2:
        check(rows[1][1] == 0, "pe64-executable: .bss carries %d file bytes" % rows[1][1])
        check(rows[1][2] == 64, "pe64-executable: .bss virtual size is %d, expected 64" % rows[1][2])


def check_pe64_imports(image: bytes) -> None:
    rows = sections_of(image)
    names = [row[0] for row in rows]
    check(b".idata" in names, "pe64-imports: no .idata section")

    rva, size = directory(image, 1)
    check(rva != 0 and size > 0, "pe64-imports: no import directory registered")
    check(size % 20 == 0, "pe64-imports: import directory size %d is not a multiple of 20" % size)

    # Walk the descriptor table: 20 bytes per DLL, terminated by a null entry.
    offset = rva_to_offset(image, rva)
    check(offset is not None, "pe64-imports: import directory RVA cannot be mapped to a file offset")
    if offset is None:
        return

    libraries: list[tuple[str, list[str]]] = []
    cursor = offset
    while True:
        lookup_rva, _stamp, _forward, name_rva, address_rva = struct.unpack_from("<IIIII", image, cursor)
        if lookup_rva == 0 and name_rva == 0 and address_rva == 0:
            break
        name_offset = rva_to_offset(image, name_rva)
        check(name_offset is not None, "pe64-imports: DLL name RVA cannot be mapped")
        if name_offset is None:
            return
        end = image.index(b"\0", name_offset)
        library = image[name_offset:end].decode("ascii", "replace")

        symbols: list[str] = []
        thunk_offset = rva_to_offset(image, lookup_rva)
        check(thunk_offset is not None, "pe64-imports: lookup table RVA cannot be mapped")
        if thunk_offset is None:
            return
        thunk = thunk_offset
        while True:
            value = struct.unpack_from("<Q", image, thunk)[0]
            if value == 0:
                break
            check(not (value & 0x8000000000000000), "pe64-imports: unexpected ordinal import")
            hint_offset = rva_to_offset(image, value & 0x7FFFFFFF)
            check(hint_offset is not None, "pe64-imports: hint/name RVA cannot be mapped")
            if hint_offset is None:
                return
            text_end = image.index(b"\0", hint_offset + 2)
            symbols.append(image[hint_offset + 2 : text_end].decode("ascii", "replace"))
            thunk += 8
        libraries.append((library, symbols))
        cursor += 20

    check(len(libraries) == 2, "pe64-imports: %d import libraries, expected 2" % len(libraries))
    if len(libraries) == 2:
        check(libraries[0][0] == "KERNEL32.DLL", "pe64-imports: first library is %r" % libraries[0][0])
        check(
            libraries[0][1] == ["ExitProcess", "GetCurrentProcessId"],
            "pe64-imports: KERNEL32 imports are %r" % libraries[0][1],
        )
        check(libraries[1][0] == "ADVAPI32.DLL", "pe64-imports: second library is %r" % libraries[1][0])
        # The local slot name must not reach the file: only the real API name does.
        check(libraries[1][1] == ["RegCloseKey"], "pe64-imports: ADVAPI32 imports are %r" % libraries[1][1])


def check_pe64_dll_exports(image: bytes) -> None:
    offset = pe_offset(image)
    characteristics = struct.unpack_from("<H", image, offset + 22)[0]
    check(characteristics & 0x2000, "pe64-dll-exports: IMAGE_FILE_DLL is not set")

    rva, size = directory(image, 0)
    check(rva != 0 and size > 0, "pe64-dll-exports: no export directory registered")

    base = rva_to_offset(image, rva)
    check(base is not None, "pe64-dll-exports: export directory RVA cannot be mapped")
    if base is None:
        return

    name_rva, ordinal_base, function_count, name_count = struct.unpack_from("<IIII", image, base + 12)
    check(function_count == 3, "pe64-dll-exports: %d exported functions, expected 3" % function_count)
    check(name_count == 3, "pe64-dll-exports: %d export names, expected 3" % name_count)
    check(ordinal_base == 1, "pe64-dll-exports: ordinal base is %d, expected 1" % ordinal_base)

    dll_offset = rva_to_offset(image, name_rva)
    check(dll_offset is not None, "pe64-dll-exports: DLL name RVA cannot be mapped")
    if dll_offset is not None:
        end = image.index(b"\0", dll_offset)
        dll_name = image[dll_offset:end].decode("ascii", "replace")
        check(dll_name == "xirasm_demo.dll", "pe64-dll-exports: DLL name is %r" % dll_name)

    names_rva = struct.unpack_from("<I", image, base + 32)[0]
    names_offset = rva_to_offset(image, names_rva)
    check(names_offset is not None, "pe64-dll-exports: name pointer table cannot be mapped")
    if names_offset is None:
        return

    names: list[str] = []
    for index in range(name_count):
        entry_rva = struct.unpack_from("<I", image, names_offset + 4 * index)[0]
        entry_offset = rva_to_offset(image, entry_rva)
        if entry_offset is None:
            check(False, "pe64-dll-exports: export name RVA cannot be mapped")
            return
        end = image.index(b"\0", entry_offset)
        names.append(image[entry_offset:end].decode("ascii", "replace"))

    check(names == ["x_add7", "x_answer", "x_sub3"], "pe64-dll-exports: export names are %r" % names)
    # The name pointer table must be sorted, which the format layer does itself.
    check(names == sorted(names), "pe64-dll-exports: export names are not sorted")


def check_pe64_relocations(image: bytes) -> None:
    flags = dll_characteristics(image)
    check(flags & 0x40, "pe64-relocations: DYNAMIC_BASE is not set although ASLR is required")
    check(flags & 0x100, "pe64-relocations: NX_COMPAT is not set")

    rva, size = directory(image, 5)
    check(rva != 0 and size > 0, "pe64-relocations: no relocation directory registered")

    rows = {row[0]: row for row in sections_of(image)}
    check(b".reloc" in rows, "pe64-relocations: no .reloc section")
    if b".reloc" not in rows:
        return
    check(rows[b".reloc"][3] == rva, "pe64-relocations: relocation directory does not point at .reloc")

    offset = rva_to_offset(image, rva)
    check(offset is not None, "pe64-relocations: relocation RVA cannot be mapped")
    if offset is None:
        return

    page_rva, block_size = struct.unpack_from("<II", image, offset)
    check(block_size == 12, "pe64-relocations: block size is %d, expected 12 (8 header + 2 entry + 2 terminator)" % block_size)

    entry = struct.unpack_from("<H", image, offset + 8)[0]
    kind = entry >> 12
    check(kind == 10, "pe64-relocations: relocation type is %d, expected 10 (IMAGE_REL_BASED_DIR64)" % kind)
    check(entry & 0xFFF == 0, "pe64-relocations: relocation offset is 0x%X, expected 0" % (entry & 0xFFF))

    # The record must name the slot in .data, not the function it points at.
    data = rows.get(b".data")
    check(data is not None, "pe64-relocations: no .data section")
    if data is not None:
        check(page_rva == data[3], "pe64-relocations: relocation page 0x%X is not .data at 0x%X" % (page_rva, data[3]))

    terminator = struct.unpack_from("<H", image, offset + 10)[0]
    check(terminator == 0, "pe64-relocations: block lacks its zero terminator")


def check_pe64_checksum(image: bytes) -> None:
    stored = struct.unpack_from("<I", image, optional_header(image) + 64)[0]
    check(stored != 0, "pe64-checksum: CheckSum field is zero")

    # Verify against the algorithm from the specification, not against the file.
    expected = pe_checksum(image)
    check(
        stored == expected,
        "pe64-checksum: CheckSum is 0x%X, the specification computes 0x%X" % (stored, expected),
    )


# --- shared ELF readers ------------------------------------------------------


def elf_sections(image: bytes) -> list[tuple[int, int, int, int, int, int]]:
    """Return (name_offset, type, flags, address, offset, size) per section."""
    shoff = struct.unpack_from("<Q", image, 40)[0]
    shentsize, shnum = struct.unpack_from("<HH", image, 58)
    rows = []
    for index in range(shnum):
        entry = shoff + shentsize * index
        name, kind = struct.unpack_from("<II", image, entry)
        flags, address, offset, size = struct.unpack_from("<QQQQ", image, entry + 8)
        rows.append((name, kind, flags, address, offset, size))
    return rows


def elf_section_names(image: bytes) -> list[str]:
    """Resolve section names through the section header string table."""
    rows = elf_sections(image)
    if not rows:
        return []
    shstrndx = struct.unpack_from("<H", image, 62)[0]
    if shstrndx >= len(rows):
        return []
    table = rows[shstrndx][4]
    names = []
    for name_offset, *_ in rows:
        start = table + name_offset
        end = image.index(b"\0", start)
        names.append(image[start:end].decode("ascii", "replace"))
    return names


def elf_symbols(image: bytes, kind: str = ".dynsym") -> list[tuple[str, int, int, int]]:
    """Return (name, value, size, type) for each entry of one symbol table.

    `kind` selects the dynamic symbol table by default, falling back to the
    ordinary one; both are laid out the same way, 24 bytes per entry.
    """
    rows = elf_sections(image)
    names = elf_section_names(image)
    chosen = None
    for index, name in enumerate(names):
        if name == kind:
            chosen = index
            break
    if chosen is None:
        for index, name in enumerate(names):
            if name in (".symtab", ".dynsym"):
                chosen = index
                break
    if chosen is None:
        return []

    _n, _t, _f, _a, offset, size = rows[chosen]
    strtab = rows[chosen + 1][4]
    symbols = []
    for at in range(offset, offset + size, 24):
        name_offset, info, _other, _shndx, value, sym_size = struct.unpack_from("<IBBHQQ", image, at)
        end = image.index(b"\0", strtab + name_offset)
        symbols.append((image[strtab + name_offset : end].decode("ascii", "replace"), value, sym_size, info & 0xF))
    return symbols


def elf_relocations(image: bytes) -> list[tuple[int, int, int, int]]:
    """Return (offset, type, symbol index, addend) from every RELA section.

    A file keeps one RELA section per relocated section, so `.rela.text` and
    `.rela.data` are separate; the entries of both belong to the same picture.
    """
    rows = elf_sections(image)
    names = elf_section_names(image)
    entries = []
    for index, name in enumerate(names):
        if not name.startswith(".rela"):
            continue
        _n, _t, _f, _a, offset, size = rows[index]
        for at in range(offset, offset + size, 24):
            r_offset, r_info, addend = struct.unpack_from("<QQq", image, at)
            entries.append((r_offset, r_info & 0xFFFFFFFF, r_info >> 32, addend))
    return entries


def elf_vaddr_to_offset(image: bytes, address: int) -> int | None:
    """Map a virtual address to a file offset through the program headers.

    A compact ELF image carries no section headers, so the program headers are
    the only way to reach the dynamic tables.
    """
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    for index in range(phnum):
        at = phoff + phentsize * index
        p_type = struct.unpack_from("<I", image, at)[0]
        if p_type != 1:
            continue
        p_offset, p_vaddr = struct.unpack_from("<QQ", image, at + 8)
        p_filesz = struct.unpack_from("<Q", image, at + 32)[0]
        if p_vaddr <= address < p_vaddr + p_filesz:
            return p_offset + (address - p_vaddr)
    return None


def elf_dynamic(image: bytes) -> dict[int, int]:
    """Return the DT_* tag values of the PT_DYNAMIC segment."""
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    for index in range(phnum):
        at = phoff + phentsize * index
        p_type = struct.unpack_from("<I", image, at)[0]
        if p_type != 2:
            continue
        p_offset, p_filesz = struct.unpack_from("<QQ", image, at + 8)
        entries = {}
        for entry in range(p_offset, p_offset + p_filesz, 16):
            tag, value = struct.unpack_from("<QQ", image, entry)
            if tag == 0:
                break
            # A repeated tag (DT_NEEDED) keeps the first value; callers that
            # need every occurrence decode the segment themselves.
            entries.setdefault(tag, value)
        return entries
    return {}


def elf_dyn_symbols(image: bytes) -> list[tuple[str, int, int, int]]:
    """Return (name, value, size, type) from the DT_SYMTAB dynamic symbol table."""
    dynamic = elf_dynamic(image)
    if 6 not in dynamic or 5 not in dynamic:
        return []

    symbols_offset = elf_vaddr_to_offset(image, dynamic[6])
    strings_offset = elf_vaddr_to_offset(image, dynamic[5])
    entry_size = dynamic.get(11, 24)
    strings_size = dynamic.get(10, 0)
    if symbols_offset is None or strings_offset is None:
        return []

    # Walk until the string table runs out: the symbol table has no explicit
    # count, and a compact image records no section headers to bound it.
    symbols = []
    at = symbols_offset
    while at + entry_size <= len(image):
        name_offset, info, _other, _shndx, value, size = struct.unpack_from("<IBBHQQ", image, at)
        if name_offset >= strings_size:
            break
        end = image.index(b"\0", strings_offset + name_offset)
        symbols.append((image[strings_offset + name_offset : end].decode("ascii", "replace"), value, size, info & 0xF))
        at += entry_size
    return symbols


# --- chapter 3: Linux ELF executables and shared objects ----------------------


def check_elf64_executable(image: bytes) -> None:
    check(image[:4] == b"\x7fELF", "elf64-executable: no ELF magic")
    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 2, "elf64-executable: e_type is %d, expected 2 (ET_EXEC)" % e_type)
    check(e_machine == 62, "elf64-executable: e_machine is %d, expected 62" % e_machine)

    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    check(phnum == 3, "elf64-executable: %d program headers, expected 3" % phnum)

    segments = []
    for index in range(phnum):
        at = phoff + phentsize * index
        p_type, p_flags = struct.unpack_from("<II", image, at)
        p_offset, p_vaddr = struct.unpack_from("<QQ", image, at + 8)
        p_filesz, p_memsz, p_align = struct.unpack_from("<QQQ", image, at + 32)
        segments.append((p_type, p_flags, p_offset, p_vaddr, p_filesz, p_memsz, p_align))
        check(p_type == 1, "elf64-executable: program header %d is not PT_LOAD" % index)
        check(
            p_offset % p_align == p_vaddr % p_align,
            "elf64-executable: segment %d is not offset/address page-congruent" % index,
        )

    if len(segments) == 3:
        text, data, bss = segments
        check((text[1], text[4], text[5]) == (5, 9, 9), "elf64-executable: .text segment is %r" % (text,))
        check((data[1], data[4], data[5]) == (6, 4, 4), "elf64-executable: .data segment is %r" % (data,))
        # BSS is the whole point of the segment: no file bytes, 128 bytes of memory.
        check(bss[4] == 0, "elf64-executable: .bss has %d file bytes, expected 0" % bss[4])
        check(bss[5] == 128, "elf64-executable: .bss memory size is %d, expected 128" % bss[5])


def check_elf64_pie(image: bytes) -> None:
    check(image[:4] == b"\x7fELF", "elf64-pie: no ELF magic")
    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 3, "elf64-pie: e_type is %d, expected 3 (ET_DYN)" % e_type)
    check(e_machine == 62, "elf64-pie: e_machine is %d, expected 62" % e_machine)

    entry = struct.unpack_from("<Q", image, 24)[0]
    check(entry != 0, "elf64-pie: entry is zero")

    # A PIE must not carry an absolute dynamic relocation for its own labels;
    # the example reaches every label through RIP-relative references.
    check(not elf_relocations(image), "elf64-pie: a dynamic relocation table is present")


def check_elf64_exe_imports(image: bytes) -> None:
    e_type = struct.unpack_from("<H", image, 16)[0]
    check(e_type == 2, "elf64-exe-imports: e_type is %d, expected 2 (ET_EXEC)" % e_type)

    # A compact image carries no section headers, so the dynamic tables are
    # reached through the program headers.
    shnum = struct.unpack_from("<H", image, 60)[0]
    check(shnum == 0, "elf64-exe-imports: %d section headers, expected none" % shnum)

    dynamic = elf_dynamic(image)
    check(2 in dynamic, "elf64-exe-imports: no PT_DYNAMIC segment")
    check(6 in dynamic, "elf64-exe-imports: no DT_SYMTAB")
    check(5 in dynamic, "elf64-exe-imports: no DT_STRTAB")
    check(23 in dynamic, "elf64-exe-imports: no DT_JMPREL (no PLT relocations)")

    symbols = {name: (value, size, kind) for name, value, size, kind in elf_dyn_symbols(image)}
    for wanted in ("getpid", "getppid", "cos"):
        check(wanted in symbols, "elf64-exe-imports: %s is not in the dynamic symbol table" % wanted)
        if wanted in symbols:
            # An imported function stays undefined so the loader resolves it.
            check(symbols[wanted][0] == 0, "elf64-exe-imports: %s already has a value" % wanted)
            check(symbols[wanted][2] == 2, "elf64-exe-imports: %s is not a function symbol" % wanted)
    # The local prefix must not leak into the file; only the real name is emitted.
    check("cos_fn" not in symbols, "elf64-exe-imports: the local prefix cos_fn was exported")

    # Both libraries must appear as DT_NEEDED entries.
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    needed = []
    for index in range(phnum):
        at = phoff + phentsize * index
        if struct.unpack_from("<I", image, at)[0] != 2:
            continue
        p_offset, p_filesz = struct.unpack_from("<QQ", image, at + 8)
        strings_offset = elf_vaddr_to_offset(image, dynamic.get(5, 0))
        for entry in range(p_offset, p_offset + p_filesz, 16):
            tag, value = struct.unpack_from("<QQ", image, entry)
            if tag == 0:
                break
            if tag == 1 and strings_offset is not None:
                end = image.index(b"\0", strings_offset + value)
                needed.append(image[strings_offset + value : end].decode("ascii", "replace"))
    for library in ("libc.so.6", "libm.so.6"):
        check(library in needed, "elf64-exe-imports: %s is not recorded as needed (%r)" % (library, needed))


def check_elf64_so_exports(image: bytes) -> None:
    e_type = struct.unpack_from("<H", image, 16)[0]
    check(e_type == 3, "elf64-so-exports: e_type is %d, expected 3 (ET_DYN)" % e_type)

    soname = struct.unpack_from("<H", image, 62)[0]
    check(soname != 0, "elf64-so-exports: no section header string table")

    symbols = {name: (value, size, kind) for name, value, size, kind in elf_symbols(image)}
    for name, size in (("x_add7", 4), ("x_sub3", 4), ("x_answer", 6)):
        check(name in symbols, "elf64-so-exports: %s is not exported" % name)
        if name in symbols:
            check(symbols[name][1] == size, "elf64-so-exports: %s has size %d, expected %d" % (name, symbols[name][1], size))
            check(symbols[name][2] == 2, "elf64-so-exports: %s is not a function symbol" % name)
    # The public name is exported; the internal label behind it is not.
    check("answer_impl" not in symbols, "elf64-so-exports: the internal label answer_impl is exported")

    text = image.decode("latin-1")
    check("libxirasm_demo.so" in text, "elf64-so-exports: the SONAME is missing")


# --- chapter 4: COFF and ELF object files ------------------------------------


def coff_symbols(image: bytes) -> list[tuple[str, int, int, int]]:
    """Return (name, value, section, type) for each COFF symbol table entry.

    The COFF file header starts at offset 0 and holds the symbol table pointer
    and count at offsets 8 and 12; an object file has no MZ stub and no PE
    signature in front of it.
    """
    table = struct.unpack_from("<I", image, 8)[0]
    count = struct.unpack_from("<I", image, 12)[0]
    string_table = table + 18 * count
    symbols = []
    index = 0
    while index < count:
        at = table + 18 * index
        raw = image[at : at + 8]
        if raw[:4] == b"\0\0\0\0":
            start = string_table + struct.unpack_from("<I", raw, 4)[0]
            end = image.index(b"\0", start)
            name = image[start:end].decode("ascii", "replace")
        else:
            name = raw.rstrip(b"\0").decode("ascii", "replace")
        value, section, sym_type = struct.unpack_from("<IhH", image, at + 8)
        symbols.append((name, value, section, sym_type))
        # A symbol with aux records occupies more than one slot.
        aux = image[at + 17]
        index += 1 + aux
    return symbols


def check_coff64_object(image: bytes) -> None:
    check(image[:2] != b"MZ", "coff64-object: the file carries an MZ header, so it is an image not an object")
    machine = struct.unpack_from("<H", image, 0)[0]
    check(machine == 0x8664, "coff64-object: machine is 0x%04x, expected 0x8664" % machine)

    section_count = struct.unpack_from("<H", image, 2)[0]
    check(section_count == 3, "coff64-object: %d sections, expected 3" % section_count)

    # An object file defines no entry point: the optional header is absent.
    optional_size = struct.unpack_from("<H", image, 16)[0]
    check(optional_size == 0, "coff64-object: OptionalHeaderSize is %d, expected 0" % optional_size)

    symbols = {name: (value, section, sym_type) for name, value, section, sym_type in coff_symbols(image)}
    for name in ("main", "answer", "scratch", "puts"):
        check(name in symbols, "coff64-object: symbol %s is missing" % name)
    if "puts" in symbols:
        # An external symbol is undefined and carries no section number.
        check(symbols["puts"][1] == 0, "coff64-object: puts is not undefined (section %d)" % symbols["puts"][1])
    if "main" in symbols:
        # The stored value is the offset inside the section, which is zero here.
        check(symbols["main"][0] == 0, "coff64-object: main has value %d, expected 0" % symbols["main"][0])
        check(symbols["main"][1] == 1, "coff64-object: main is not in section 1 (.text)")
        check(symbols["main"][2] & 0x20, "coff64-object: main is not marked as a function")


def check_elfobj64_object(image: bytes) -> None:
    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 1, "elfobj64-object: e_type is %d, expected 1 (ET_REL)" % e_type)
    check(e_machine == 62, "elfobj64-object: e_machine is %d, expected 62" % e_machine)

    # A relocatable file has no program headers.
    phnum = struct.unpack_from("<H", image, 56)[0]
    check(phnum == 0, "elfobj64-object: %d program headers, expected none" % phnum)

    names = elf_section_names(image)
    for wanted in (".text", ".bss", ".rodata"):
        check(wanted in names, "elfobj64-object: section %s is missing" % wanted)

    symbols = {name: (value, size, kind) for name, value, size, kind in elf_symbols(image)}
    for name, size, kind in (("_start", 8, 2), ("scratch", 64, 1), ("answer", 4, 1)):
        check(name in symbols, "elfobj64-object: symbol %s is missing" % name)
        if name in symbols:
            check(symbols[name][1] == size, "elfobj64-object: %s has size %d, expected %d" % (name, symbols[name][1], size))
            check(symbols[name][2] == kind, "elfobj64-object: %s has type %d, expected %d" % (name, symbols[name][2], kind))
    check("puts" in symbols, "elfobj64-object: external symbol puts is missing")

    relocs = elf_relocations(image)
    check(len(relocs) == 1, "elfobj64-object: %d relocations, expected 1" % len(relocs))
    if relocs:
        offset, kind, _symbol, addend = relocs[0]
        check(kind == 4, "elfobj64-object: relocation type is %d, expected 4 (R_X86_64_PLT32)" % kind)
        # The addend is the width of the displacement field itself, per the psABI.
        check(addend == -4, "elfobj64-object: relocation addend is %d, expected -4" % addend)
        check(offset == 1, "elfobj64-object: relocation offset is %d, expected 1" % offset)


def check_elfobj64_aarch64(image: bytes) -> None:
    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 1, "elfobj64-aarch64: e_type is %d, expected 1 (ET_REL)" % e_type)
    check(e_machine == 183, "elfobj64-aarch64: e_machine is %d, expected 183 (EM_AARCH64)" % e_machine)

    relocs = elf_relocations(image)
    check(len(relocs) == 4, "elfobj64-aarch64: %d relocations, expected 4" % len(relocs))
    # R_AARCH64_ABS64=257, ADR_PREL_PG_HI21=275, ADD_ABS_LO12_NC=277, CALL26=283.
    # `.rela.text` holds the three instruction records at offsets 0, 4, and 8;
    # `.rela.data` holds the absolute-pointer record.
    by_section = sorted((offset, kind) for offset, kind, _symbol, _addend in relocs if kind in (275, 277, 283))
    check(
        by_section == [(0, 283), (4, 275), (8, 277)],
        "elfobj64-aarch64: instruction relocations are %r" % (by_section,),
    )
    absolute = [(offset, kind) for offset, kind, _symbol, _addend in relocs if kind == 257]
    check(absolute == [(0, 257)], "elfobj64-aarch64: absolute relocations are %r" % (absolute,))


def check_linux_write_and_exit(image: bytes) -> None:
    """The real Linux program: two segments, code apart from read-only data."""
    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 2, "linux-write-and-exit: e_type is %d, expected 2 (ET_EXEC)" % e_type)
    check(e_machine == 62, "linux-write-and-exit: e_machine is %d, expected 62" % e_machine)

    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    check(phnum == 2, "linux-write-and-exit: %d program headers, expected 2" % phnum)

    segments = []
    for index in range(phnum):
        at = phoff + phentsize * index
        p_type, p_flags = struct.unpack_from("<II", image, at)
        p_offset, p_vaddr = struct.unpack_from("<QQ", image, at + 8)
        p_filesz, p_memsz, p_align = struct.unpack_from("<QQQ", image, at + 32)
        segments.append((p_type, p_flags, p_offset, p_filesz, p_memsz, p_align))
        check(p_type == 1, "linux-write-and-exit: program header %d is not PT_LOAD" % index)
        check(
            p_offset % p_align == p_vaddr % p_align,
            "linux-write-and-exit: segment %d is not offset/address page-congruent" % index,
        )

    if len(segments) == 2:
        code, rodata = segments
        # Code is readable and executable; data is readable only.
        check(code[1] == 5, "linux-write-and-exit: .text flags are %d, expected 5 (R|X)" % code[1])
        check(code[3] == 47, "linux-write-and-exit: .text file size is %d, expected 47" % code[3])
        check(rodata[1] == 4, "linux-write-and-exit: .rodata flags are %d, expected 4 (R)" % rodata[1])
        check(rodata[3] == 48, "linux-write-and-exit: .rodata file size is %d, expected 48" % rodata[3])

    # The message the example prints, including its trailing newline.
    check(b"xirasm: exit status carries the computed result\n" in image, "linux-write-and-exit: the message is missing")


def check_linux_libc_imports(image: bytes) -> None:
    """A real program that calls libc through the PLT."""
    e_type = struct.unpack_from("<H", image, 16)[0]
    check(e_type == 2, "linux-libc-imports: e_type is %d, expected 2 (ET_EXEC)" % e_type)

    dynamic = elf_dynamic(image)
    check(2 in dynamic, "linux-libc-imports: no PT_DYNAMIC segment")
    # Two imported functions need two 24-byte RELA entries.
    check(dynamic.get(2) == 48, "linux-libc-imports: PLTRELSZ is %r, expected 48" % dynamic.get(2))
    check(dynamic.get(20) == 7, "linux-libc-imports: PLTREL is %r, expected 7 (RELA)" % dynamic.get(20))

    check(3 in dynamic, "linux-libc-imports: no PT_INTERP (DT_DEBUG is absent from the dynamic table)")

    symbols = {name: (value, size, kind) for name, value, size, kind in elf_dyn_symbols(image)}
    for wanted in ("write", "getpid"):
        check(wanted in symbols, "linux-libc-imports: %s is not in the dynamic symbol table" % wanted)
        if wanted in symbols:
            check(symbols[wanted][0] == 0, "linux-libc-imports: %s already has a value" % wanted)

    check(b"libc.so.6" in image, "linux-libc-imports: libc.so.6 is not recorded as needed")
    check(b"/lib64/ld-linux-x86-64.so.2" in image, "linux-libc-imports: the default interpreter is missing")
    check(b"xirasm: write() came from libc through the PLT\n" in image, "linux-libc-imports: the message is missing")


def check_elfobj64_export_for_c(image: bytes) -> None:
    """An object file meant to be linked into a C program."""
    e_type, e_machine = struct.unpack_from("<HH", image, 16)
    check(e_type == 1, "elfobj64-export-for-c: e_type is %d, expected 1 (ET_REL)" % e_type)
    check(e_machine == 62, "elfobj64-export-for-c: e_machine is %d, expected 62" % e_machine)

    symbols = {name: (value, size, kind) for name, value, size, kind in elf_symbols(image, ".symtab")}
    check("xirasm_double" in symbols, "elfobj64-export-for-c: xirasm_double is not defined")
    if "xirasm_double" in symbols:
        value, size, kind = symbols["xirasm_double"]
        # The symbol must be a global function of four bytes for the C caller.
        check(value == 0, "elfobj64-export-for-c: xirasm_double has value %d, expected 0" % value)
        check(size == 4, "elfobj64-export-for-c: xirasm_double has size %d, expected 4" % size)
        check(kind == 2, "elfobj64-export-for-c: xirasm_double is not a function symbol (type %d)" % kind)

    # The function is self-contained, so the object carries no relocations.
    check(not elf_relocations(image), "elfobj64-export-for-c: unexpected relocation records")


def bss_row(image: bytes) -> tuple[bytes, int, int, int, int, int] | None:
    """Return the `.bss` section row as (name, raw_size, virtual_size, chars, ...)."""
    offset = pe_offset(image)
    optional_size = struct.unpack_from("<H", image, offset + 20)[0]
    table = offset + 24 + optional_size
    count = struct.unpack_from("<H", image, offset + 6)[0]
    for index in range(count):
        entry = table + 40 * index
        if image[entry : entry + 8].rstrip(b"\0") == b".bss":
            virtual_size = struct.unpack_from("<I", image, entry + 8)[0]
            file_size = struct.unpack_from("<I", image, entry + 16)[0]
            chars = struct.unpack_from("<I", image, entry + 36)[0]
            return (b".bss", file_size, virtual_size, chars, entry, table)
    return None


def check_bss_with_bytes(image: bytes) -> None:
    """The mistake: a section marked uninitialized that still carries file bytes.

    `format.inc` does not reject this. The section keeps
    IMAGE_SCN_CNT_UNINITIALIZED_DATA while its raw size stops being zero, so the
    declaration and the bytes disagree — which is what the chapter warns about.
    """
    row = bss_row(image)
    check(row is not None, "bss-with-bytes: no .bss section")
    if row is None:
        return
    _name, file_size, virtual_size, chars, _entry, _table = row
    check(chars & 0x80, "bss-with-bytes: .bss lost IMAGE_SCN_CNT_UNINITIALIZED_DATA")
    # The load-bearing assertion: writing real bytes gives the section file content.
    check(file_size != 0, "bss-with-bytes: .bss carries no file bytes, so the example no longer shows the mistake")
    check(virtual_size == 8, "bss-with-bytes: .bss virtual size is %d, expected 8" % virtual_size)
    check(image[0x400:0x408] == bytes([0x44, 0x33, 0x22, 0x11, 0x88, 0x77, 0x66, 0x55]),
          "bss-with-bytes: the written bytes are not in the file at the .bss raw pointer")


def check_bss_reserved_only(image: bytes) -> None:
    """The correct form: the same section with `rb(8)` and no file bytes."""
    row = bss_row(image)
    check(row is not None, "bss-reserved-only: no .bss section")
    if row is None:
        return
    _name, file_size, virtual_size, chars, _entry, _table = row
    check(chars & 0x80, "bss-reserved-only: .bss is not marked uninitialized data")
    check(file_size == 0, "bss-reserved-only: .bss carries %d file bytes, expected 0" % file_size)
    check(virtual_size == 8, "bss-reserved-only: .bss virtual size is %d, expected 8" % virtual_size)


def check_idata_after_begin(image: bytes) -> None:
    """A PE import section generated after `format_begin` still registers.

    The guide used to require attaching PE section generators before
    `format_begin`; this fixture records what actually happens.
    """
    rva, size = directory(image, 1)
    check(rva != 0 and size > 0, "idata-after-begin: the import directory was not registered")
    # One DLL descriptor plus its null terminator is 40 bytes.
    check(size == 40, "idata-after-begin: import directory size is %d, expected 40" % size)

    rows = sections_of(image)
    check(b".idata" in [row[0] for row in rows], "idata-after-begin: no .idata section")
    offset = rva_to_offset(image, rva)
    check(offset is not None, "idata-after-begin: the import directory RVA cannot be mapped")
    if offset is None:
        return
    lookup_rva, _stamp, _forward, name_rva, _address = struct.unpack_from("<IIIII", image, offset)
    check(lookup_rva != 0, "idata-after-begin: the descriptor has no lookup table")
    name_offset = rva_to_offset(image, name_rva)
    check(name_offset is not None, "idata-after-begin: the DLL name RVA cannot be mapped")
    if name_offset is not None:
        end = image.index(b"\0", name_offset)
        check(image[name_offset:end] == b"KERNEL32.DLL", "idata-after-begin: the DLL name is wrong")


def check_pe64_resources(image: bytes) -> None:
    """A PE image carrying a compiled resource tree."""
    rows = sections_of(image)
    names = [row[0] for row in rows]
    check(b".rsrc" in names, "pe64-resources: no .rsrc section")

    # Resource data is data directory entry 2 (index 2 in the 16-entry table).
    rva, size = directory(image, 2)
    check(rva != 0 and size > 0, "pe64-resources: the resource directory was not registered")
    check(size == 364, "pe64-resources: resource directory size is %d, expected 364" % size)

    for row in rows:
        if row[0] == b".rsrc":
            # The section declares resources and is readable; its content is real.
            check(row[2] == 364, "pe64-resources: .rsrc virtual size is %d, expected 364" % row[2])
            check(row[1] > 0, "pe64-resources: .rsrc carries no file bytes")
    offset = rva_to_offset(image, rva)
    check(offset is not None, "pe64-resources: the resource directory RVA cannot be mapped")
    if offset is None:
        return
    # A resource directory starts with four counts; the tree is non-empty.
    named, ids = struct.unpack_from("<HH", image, offset + 12)
    check(named + ids > 0, "pe64-resources: the resource root directory has no entries")


# --- Mach-O ------------------------------------------------------------------


def macho_header(image: bytes) -> tuple[int, int, int, int]:
    """Return (magic, cpu_type, file_type, load_command_count) for a 64-bit Mach-O."""
    magic, cpu_type, _cpu_subtype, file_type, command_count = struct.unpack_from("<IIIII", image, 0)
    return (magic, cpu_type, file_type, command_count)


def macho_load_commands(image: bytes) -> list[tuple[int, int]]:
    """Return (command, size) for each load command."""
    _magic, _cpu, _file, count = macho_header(image)
    size_of_commands = struct.unpack_from("<I", image, 20)[0]
    commands = []
    at = 32
    end = 32 + size_of_commands
    for _ in range(count):
        if at + 8 > end:
            break
        command, command_size = struct.unpack_from("<II", image, at)
        commands.append((command, command_size))
        if command_size < 8:
            break
        at += command_size
    return commands


def check_macho64_exe(image: bytes) -> None:
    magic, cpu_type, file_type, command_count = macho_header(image)
    check(magic == 0xFEEDFACF, "macho64-exe: magic is 0x%X, expected 0xFEEDFACF" % magic)
    check(cpu_type == 0x01000007, "macho64-exe: cpu type is 0x%X, expected x86-64" % cpu_type)
    check(file_type == 2, "macho64-exe: file type is %d, expected 2 (MH_EXECUTE)" % file_type)
    # The facade writes __PAGEZERO, __TEXT, __LINKEDIT, LC_LOAD_DYLINKER, LC_MAIN,
    # and LC_BUILD_VERSION, so the chapter states six commands.
    check(command_count == 6, "macho64-exe: %d load commands, expected 6" % command_count)

    kinds = [command for command, _size in macho_load_commands(image)]
    check(0x19 in kinds, "macho64-exe: no LC_SEGMENT_64")
    check(0x80000028 in kinds, "macho64-exe: no LC_MAIN")
    check(0xE in kinds, "macho64-exe: no LC_LOAD_DYLINKER")
    check(0x32 in kinds, "macho64-exe: no LC_BUILD_VERSION")
    # Three segments carry the three LC_SEGMENT_64 commands: __PAGEZERO, __TEXT,
    # __LINKEDIT.
    check(kinds.count(0x19) == 3, "macho64-exe: %d segments, expected 3" % kinds.count(0x19))

    # The single declared section holds the three code bytes the example writes.
    check(b"\x31\xc0\xc3" in image, "macho64-exe: the code bytes are missing")


def check_macho64_object(image: bytes) -> None:
    magic, cpu_type, file_type, command_count = macho_header(image)
    check(magic == 0xFEEDFACF, "macho64-object: magic is 0x%X, expected 0xFEEDFACF" % magic)
    check(cpu_type == 0x0100000C, "macho64-object: cpu type is 0x%X, expected arm64" % cpu_type)
    check(file_type == 1, "macho64-object: file type is %d, expected 1 (MH_OBJECT)" % file_type)

    kinds = [command for command, _size in macho_load_commands(image)]
    check(0x19 in kinds, "macho64-object: no LC_SEGMENT_64")
    check(0x2 in kinds, "macho64-object: no LC_SYMTAB")
    check(command_count == 3, "macho64-object: %d load commands, expected 3" % command_count)

    # The example declares two globals and one external, and writes four
    # relocation records for the placeholder words.
    for name in (b"_entry", b"_answer", b"_printf"):
        check(name in image, "macho64-object: symbol %s is missing" % name.decode())

    # The first load command is LC_SEGMENT_64; its nsects field sits at offset 64.
    section_count = struct.unpack_from("<I", image, 32 + 64)[0]
    check(section_count == 2, "macho64-object: segment reports %d sections, expected 2" % section_count)


def check_pe64_reloc_probe(image: bytes) -> None:
    """A DLL whose relocation the Windows loader must apply.

    The example exists to make the relocation observable: the host reads an
    absolute pointer back out of .data and calls it. That only works when the
    loader rewrote the slot, so the fixture must carry a real DIR64 record whose
    target is the slot itself.
    """
    offset = pe_offset(image)
    characteristics = struct.unpack_from("<H", image, offset + 22)[0]
    check(characteristics & 0x2000, "pe64-reloc-probe: IMAGE_FILE_DLL is not set")

    flags = dll_characteristics(image)
    check(flags & 0x40, "pe64-reloc-probe: DYNAMIC_BASE is not set, so the loader will not relocate")
    check(flags & 0x100, "pe64-reloc-probe: NX_COMPAT is not set")

    rows = {row[0]: row for row in sections_of(image)}
    for wanted in (b".text", b".data", b".edata", b".reloc"):
        check(wanted in rows, "pe64-reloc-probe: no %s section" % wanted.decode())

    rva, size = directory(image, 5)
    check(rva != 0 and size > 0, "pe64-reloc-probe: no relocation directory registered")
    check(size == 12, "pe64-reloc-probe: relocation directory size is %d, expected 12" % size)

    block = rva_to_offset(image, rva)
    check(block is not None, "pe64-reloc-probe: the relocation RVA cannot be mapped")
    if block is None:
        return
    page_rva, block_size = struct.unpack_from("<II", image, block)
    entry = struct.unpack_from("<H", image, block + 8)[0]
    # The record must name the slot in .data, not the function it points at.
    data = rows.get(b".data")
    check(data is not None, "pe64-reloc-probe: no .data section")
    if data is not None:
        check(page_rva == data[3], "pe64-reloc-probe: relocation page 0x%X is not .data at 0x%X" % (page_rva, data[3]))
    check(block_size == 12, "pe64-reloc-probe: block size is %d, expected 12" % block_size)
    check(entry >> 12 == 10, "pe64-reloc-probe: relocation type is %d, expected 10 (DIR64)" % (entry >> 12))
    check(entry & 0xFFF == 0, "pe64-reloc-probe: relocation offset is 0x%X, expected 0" % (entry & 0xFFF))

    # The exported reader is what the host calls to read the slot back.
    export_rva, export_size = directory(image, 0)
    check(export_rva != 0 and export_size > 0, "pe64-reloc-probe: no export directory registered")
    check(b"read_pointer" in image, "pe64-reloc-probe: the exported reader name is missing")
    # The slot holds an absolute address written at link time, so its value is
    # the image base plus the function RVA, not zero.
    slot = rva_to_offset(image, data[3]) if data is not None else None
    if slot is not None:
        image_base = struct.unpack_from("<Q", image, optional_header(image) + 24)[0]
        stored = struct.unpack_from("<Q", image, slot)[0]
        check(stored != 0, "pe64-reloc-probe: the slot is still zero, so no pointer was backfilled")
        check(
            stored > image_base,
            "pe64-reloc-probe: the slot holds 0x%X, which is not an address above the image base" % stored,
        )


CHECKS = {
    "pe64-minimal": check_pe64_minimal,
    "elf64-minimal": check_elf64_minimal,
    "pe64-executable": check_pe64_executable,
    "pe64-imports": check_pe64_imports,
    "pe64-dll-exports": check_pe64_dll_exports,
    "pe64-relocations": check_pe64_relocations,
    "pe64-reloc-probe": check_pe64_reloc_probe,
    "pe64-checksum": check_pe64_checksum,
    "elf64-executable": check_elf64_executable,
    "elf64-pie": check_elf64_pie,
    "elf64-exe-imports": check_elf64_exe_imports,
    "elf64-so-exports": check_elf64_so_exports,
    "linux-write-and-exit": check_linux_write_and_exit,
    "linux-libc-imports": check_linux_libc_imports,
    "coff64-object": check_coff64_object,
    "elfobj64-object": check_elfobj64_object,
    "elfobj64-export-for-c": check_elfobj64_export_for_c,
    "elfobj64-aarch64": check_elfobj64_aarch64,
    "bss-with-bytes": check_bss_with_bytes,
    "bss-reserved-only": check_bss_reserved_only,
    "idata-after-begin": check_idata_after_begin,
    "pe64-resources": check_pe64_resources,
    "macho64-exe": check_macho64_exe,
    "macho64-object": check_macho64_object,
}


def fixture_key(path: Path) -> str:
    """Strip the `<chapter>-` prefix and any `-zh` suffix from a fixture name.

    The assembled names stay unique on disk across chapters, languages, and
    targets, while the checks themselves are shared: the two languages differ in
    comments only, and the same structure holds for either target.
    """
    stem = path.stem
    head, separator, tail = stem.partition("-")
    if separator and head.isdigit():
        stem = tail
    for suffix in ("-zh", "-a64"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
    return stem


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    checked = 0
    for argument in argv[1:]:
        path = Path(argument)
        key = fixture_key(path)
        run = CHECKS.get(key)
        if run is None:
            FAILURES.append("%s: no checks for fixture %r" % (path.name, key))
            continue
        if not path.is_file():
            FAILURES.append("%s: no image at %s" % (key, path))
            continue
        run(path.read_bytes())
        checked += 1
    for message in FAILURES:
        print("error: %s" % message, file=sys.stderr)
    if FAILURES:
        print("format fixtures: %d failure(s)" % len(FAILURES), file=sys.stderr)
        return 1
    print("format fixtures: %d fixture(s) match their structure" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
