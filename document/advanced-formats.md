# XIRASM Advanced Format Construction Guide

Most programs should use XIRASM's ordinary format facade:

```text
import("format/format.inc");
```

It turns declarations such as sections, segments, imports, exports, and
relocations into a complete PE, COFF, or ELF layout. It also derives the
counts, indexes, rows, offsets, and generated tables that standard files
require.

Some programs need control below that level. A custom loader may require an
unusual header arrangement. A linker experiment may need a specific relocation
row. A runtime image may need metadata that the ordinary facade does not
expose. XIRASM provides direct format helpers for those cases.

This guide explains that direct layer. It assumes that you already understand:

- the XIRASM language and output-region model;
- the ordinary format lifecycle;
- the target format's terminology and ABI;
- the difference between logical addresses and physical file offsets.

Read the [Language Guide](language.md) for the language itself and the
[Format Tutorial](format-tutorial.md) for ordinary PE, COFF, and ELF
workflows.

Direct control is not a more correct version of the ordinary facade. It is a
different responsibility boundary. The assembler exposes more of the format,
and the source must preserve more of the format's invariants.

## Guide Map

### Part I: Choosing Direct Control

1. **Choosing the Advanced Layer**
   - The ordinary facade, compatibility wrappers, and direct family helpers
2. **Coordinates, Regions, and Finalization**
   - Logical addresses, file offsets, reserve, BSS, region closure, and backfill
3. **Manual Responsibilities**
   - Counts, indexes, rows, alignments, and table relationships

### Part II: Direct PE Construction

4. **PE Headers and Section Rows**
5. **PE Imports, Exports, and Directories**
6. **PE Relocations, Resources, and Checksums**

### Part III: Direct COFF Construction

7. **COFF Sections and Symbols**
8. **COFF Relocations and Linker Interoperability**

### Part IV: Direct ELF Construction

9. **ELF Executable Program Headers**
10. **ELF Object Sections, Symbols, REL, and RELA**
11. **ELF Shared-Object Dynamic Tables, PLT, and GOT**

### Part V: Validation and Interoperability

12. **Validation and Interoperability**
    - Structural inspection, linker and loader contracts, and ABI boundaries

## Part I: Choosing Direct Control

## 1. Choosing the Advanced Layer

XIRASM exposes three format layers. They share the same language, labels,
regions, and finalization model, but they assign different responsibilities to
the source.

The three layers are:

1. the ordinary user facade;
2. width-specific compatibility wrappers;
3. direct family helpers.

Choose the highest layer that can express the required file. Moving downward
does not merely change function names. It transfers counts, indexes, addresses,
table relationships, and validation responsibilities from the facade to the
source.

### Layer 1: The Ordinary User Facade

The ordinary layer is:

```text
include/format/format.inc
```

It uses a plan-and-lifecycle model:

```text
create a plan
declare sections or segments
attach imports, exports, symbols, or relocations
begin the format
write named content
bind an entry when the format needs one
finish the format
```

The plan records relationships by name. For example, a relocation names its
target symbol, and an export names its containing section or segment. The
facade converts those relationships into numeric rows and indexes after it has
the complete declaration set.

The ordinary layer normally owns:

- section or segment counts;
- section and program-header row assignment;
- symbol indexes;
- relocation-table grouping;
- string-table offsets;
- file offsets and virtual-address placement;
- generated import and export tables;
- generated dynamic metadata;
- final header counts and directory links.

Use this layer for standard executables, DLLs, shared objects, and relocatable
objects. If the file can be described through the ordinary facade, direct
helpers usually add work without adding useful control.

The [Format Tutorial](format-tutorial.md) documents this layer completely
enough for ordinary construction. This guide does not repeat those workflows.

### Layer 2: Width-Specific Compatibility Wrappers

The compatibility wrappers are:

```text
include/format/pe32.inc
include/format/pe64.inc
include/format/elf32.inc
include/format/elf64.inc
include/format/coff32.inc
include/format/coff64.inc
```

These files provide short, width-specific names and common flag combinations.
They delegate their work to the direct family helpers.

For example, a wrapper may:

- select PE32 instead of PE64;
- select i386 COFF instead of AMD64 COFF;
- select ELF32, ELF64, or ELF64 PIE defaults;
- provide common RX, RW, or read-only flag combinations;
- select an automatic file-offset helper instead of its raw counterpart;
- combine several related finalizer calls into one width-specific procedure.

They do not provide the ordinary plan model.

A compatibility wrapper may still require the caller to supply:

- a section or segment count;
- a section or program-header row;
- a symbol count;
- a section name encoded for a header row;
- an entry label and containing section start;
- explicit relocation-table positions;
- raw file offsets when using a `_raw` function;
- the correct order of header, payload, table, and finalizer calls.

For example, `pe64_exe(section_count)` fixes the PE width but still requires an
explicit section count. `elf64_exe(segment_count)` fixes the ELF class and
default base but still requires an explicit program-header count.
`coff64_obj(section_count, symbol_count)` fixes the COFF machine type but still
requires both counts.

These wrappers remain useful when maintaining an existing source that already
uses their row-oriented workflow. They can also make a small direct example
easier to read when their defaults exactly match the required file.

They are not the preferred starting point for a new ordinary program. Their
shorter names do not remove the caller's low-level responsibilities.

### Layer 3: Direct Family Helpers

The direct layer exposes format records and finalizers by family.

PE construction begins with:

```text
include/format/pe.inc
```

Related PE helpers cover imports, exports, relocations, and resources:

```text
include/format/pe_import.inc
include/format/pe_export.inc
include/format/pe_reloc.inc
include/format/pe_resource.inc
```

COFF object construction begins with:

```text
include/format/coff.inc
```

ELF construction is divided by output model:

```text
include/format/elfexe.inc
include/format/elfobj.inc
include/format/elfso.inc
```

Additional ELF helpers construct executable imports, shared-object imports, and
exports.

At this layer, the source can call helpers that correspond closely to format
records and relationships:

- emit an executable or object header with an explicit count;
- begin a section or segment at an explicit file offset;
- select a section-table or program-header row;
- emit a symbol or relocation with an explicit numeric index;
- emit a section header, program header, dynamic row, or directory record;
- calculate a table row's physical file position;
- register stable-image finalizers for sizes, addresses, and header fields.

The direct helpers still use XIRASM's region and finalizer model. They are not
raw byte constants disguised as an API. However, they deliberately expose
format facts that the ordinary facade keeps internal.

### Responsibility Increases as the Layer Gets Lower

| Responsibility | Ordinary facade | Compatibility wrapper | Direct helper |
| --- | --- | --- | --- |
| Select format and width | Declarative plan | Width-specific entry | Explicit family entry |
| Count sections or segments | Derived | Caller-supplied | Caller-supplied |
| Assign rows | Derived by name | Caller-supplied | Caller-supplied |
| Assign symbol indexes | Derived by name | Usually caller-supplied | Caller-supplied |
| Place file data | Derived | Partly automatic or raw | Automatic or explicit |
| Relate VA/RVA to FOA | Derived | Caller participates | Caller controls |
| Generate tables | From declarations | Source orchestrates | Source orchestrates |
| Register backfill | Facade-owned | Wrapper combines helpers | Source selects helpers |
| Validate relations | Facade-owned | Shared responsibility | Source-owned |

An automatic direct helper may derive one local value, such as a section's
physical size from region facts. That does not make the complete workflow
automatic. The source still chooses the correct row, table relationship, and
call order.

### Choose the Layer by the Required Control

Use the ordinary facade when:

- the target is a standard PE, COFF, or ELF workflow;
- sections and segments can be declared before writing their contents;
- generated import, export, relocation, or dynamic tables are acceptable;
- names can describe relationships more clearly than numeric indexes;
- the source should remain easy to maintain.

Use a compatibility wrapper when:

- an existing source already follows that wrapper's row-oriented workflow;
- its width-specific defaults exactly match the required layout;
- changing the source to the plan model provides no immediate benefit;
- the remaining explicit counts and rows are intentional.

Use direct family helpers when:

- a nonstandard header field or table arrangement must be emitted;
- the source must control a specific row, index, or file offset;
- metadata must be ordered differently from the ordinary facade;
- a custom loader or linker contract requires unusual records;
- the work is explicitly about constructing or studying the file format.

Do not move to a lower layer merely because a function exists there. Start from
the required output difference, then choose the smallest amount of direct
control that can express it.

### Do Not Mix Layers Accidentally

The ordinary facade already emits headers, assigns rows, generates tables, and
registers finalizers. Calling row-oriented helpers inside the same plan can
create two owners for the same fields.

Unsafe accidental combinations include:

- beginning an ordinary PE plan and then emitting another PE header directly;
- letting the ordinary facade assign section rows while manually finalizing a
  different row number;
- attaching ordinary imports and also emitting a second import directory;
- letting the ordinary ELF facade generate program headers while manually
  patching their count;
- combining an ordinary symbol plan with separately numbered direct symbols.

This can produce a file that looks plausible but contains contradictory counts,
overlapping tables, duplicated directories, or finalizers that overwrite each
other.

Mixing levels is valid only when ownership is explicit. A direct extension must
know which fields remain facade-owned and which fields the extension replaces.
If that boundary cannot be stated precisely, use one layer for the entire
format workflow.

### Compatibility Is Not the Same as Recommendation

A compatibility wrapper is a supported source surface, but support does not
make it the best teaching layer for new code.

The wrappers preserve concise width-specific workflows. They do not promise:

- automatic discovery of section or segment counts;
- name-based symbol and relocation resolution;
- complete generated metadata;
- protection from inconsistent row numbering;
- the same validation performed by an ordinary plan.

New standard programs should begin with `format.inc`. Existing wrapper-based
programs do not need to be rewritten merely for style. Rewrite them when the
ordinary plan removes meaningful manual state or when a source is already
being restructured.

### Direct Helpers Are a Contract, Not an Escape Hatch

Direct helpers expose valid construction operations, but they do not waive the
target format's rules.

The source remains responsible for:

- using the correct machine and file type;
- keeping counts consistent with emitted records;
- keeping row and symbol indexes stable;
- preserving required alignments;
- separating logical addresses from physical file positions;
- representing BSS without accidental file payload;
- connecting directories and tables to the correct ranges;
- choosing relocation types that match the encoded fields;
- respecting loader, linker, and ABI requirements.

The remaining chapters explain those responsibilities before presenting
complete direct workflows.

### Practical Layer-Selection Rules

1. Start with `format.inc`.
2. Move lower only when a concrete output requirement cannot be expressed.
3. Treat width-specific wrappers as compatibility and convenience surfaces.
4. Do not confuse an `_auto` helper with a complete automatic format writer.
5. Use direct helpers when explicit rows, indexes, offsets, or table order are
   the purpose of the source.
6. Keep one clear owner for every header field and generated table.
7. Do not combine ordinary and direct table generation without a written
   ownership boundary.
8. Keep format API signatures in the Format API Reference rather than copying
   every helper into tutorial prose.
9. Verify direct outputs structurally and through a real linker or loader.
10. Prefer maintainability unless the required binary layout justifies the
    additional control.

Chapter 2 establishes the coordinate and finalization model used by every
direct format family: logical addresses, physical file offsets, regions,
reserve, BSS, and stable-image backfill.

## 2. Coordinates, Regions, and Finalization

Direct format construction depends on a precise answer to four questions:

1. At what address will a range exist when loaded?
2. At what position will its bytes appear in the file?
3. How much address space does the range occupy?
4. How many bytes are actually stored?

A flat binary often gives the same answer to all four questions. Executable and
object formats do not.

A PE section can begin at RVA `0x1000` while its bytes begin at file offset
`0x200`. An ELF `PT_LOAD` segment can reserve memory beyond its stored bytes.
A COFF BSS section can describe storage without contributing payload bytes.

The direct format helpers expose these distinctions. The source must preserve
them.

### The Four Facts of an Output Region

An ordinary output region has four independent layout facts:

| Fact | Meaning |
|---|---|
| Logical origin | Address assigned to the first byte or reserved unit |
| Logical size | Complete address-space extent, including reserve |
| File offset | Physical position of the region's first stored byte |
| File size | Number of bytes materialized for the region |

`region.begin(name, origin, file_offset)` chooses the first and third facts.
Normal emission and reserve determine the two sizes.

```asm
region.begin("payload", 0x401000, 0x200);

payload_start:
emit.bytes(b"ABC");
reserve(13);
payload_end:
```

At this point:

```text
logical origin = 0x401000
logical size   = 16
file offset    = 0x200
file size      = 3
```

The reserved tail belongs to the memory image but is not yet part of the file.
In flat output, the explicit FOA also creates a zero-filled gap up to `0x200`.
An executable-format layout normally places its headers in that earlier range.

These facts map to different fields in each format:

| Format | Logical facts commonly describe | Physical facts commonly describe |
|---|---|---|
| PE | RVA, virtual size, image size | raw pointer, raw size |
| COFF | section-relative extent, BSS size | raw pointer, relocation pointer |
| ELF | `p_vaddr`, `p_memsz`, allocated section address | `p_offset`, `p_filesz` |

Do not derive one coordinate from another unless the format contract explicitly
defines that relationship.

### Logical Addresses Are Not File Offsets

Labels and `here()` use the logical coordinate system:

```asm
region.begin("code", 0x401000, 0x200);

entry:
emit.u8(0xc3);

assert(label_addr("entry") == 0x401000);
assert(here() == 0x401001);
assert(file_cursor_real() == 0x201);
```

The label value is a runtime-style address. The file cursor is a physical file
position.

The common derived forms are:

```text
PE RVA             = logical address - image base
section-relative   = logical address - section start
physical FOA       = region file offset + physical offset within the region
```

An ELF virtual address is not generally `image_base + file_offset`. That
shortcut works only for layouts deliberately constructed with that mapping.
Direct layouts must preserve the actual region origin.

### Real and Potential File Cursors

XIRASM keeps two live file cursors:

| Query | Meaning |
|---|---|
| `file_cursor_real()` | End of materialized file bytes |
| `file_cursor_potential()` | End if the active reserved tail becomes physical |
| `tail_reserve_size()` | Current unmaterialized reserved tail |

Initialized bytes advance both cursors. A reserve advances only the potential
cursor until later initialized output requires the gap to exist.

```asm
emit.u8(0xaa);
reserve(3);

assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 4);
assert(tail_reserve_size() == 3);
```

If another byte is emitted in the same region, the reserved range becomes a
physical middle gap:

```asm
emit.u8(0xaa);
reserve(3);
emit.u8(0xbb);

assert(file_cursor_real() == 5);
assert(file_cursor_potential() == 5);
assert(tail_reserve_size() == 0);
```

The file now contains:

```text
aa 00 00 00 bb
```

The distinction matters whenever the next region should follow stored bytes
but the next logical address must follow the complete memory extent.

### Closing a Region

`region.file_align(alignment)` finalizes the active region's physical extent.
It first trims any unmaterialized reserved tail, then rounds the stored size to
the requested file alignment.

Use alignment `1` to close a region without adding file padding:

```asm
region.begin("first", 0x1000, 0);

first_start:
emit.bytes(b"ABC");
reserve(13);
first_end:

region.file_align(1);

const next_foa: u64 = file_cursor_real()
region.begin("second", 0x2000, next_foa);
emit.u8(0x5a);
```

The first region occupies sixteen logical bytes and three physical bytes. The
second region begins at file offset `3`.

A larger alignment changes only the physical extent:

```text
region.file_align(1)      exact physical close
region.file_align(4)      close and round to a four-byte boundary
region.file_align(0x200)  close and round to a 512-byte boundary
```

File alignment and logical alignment are separate decisions. Closing a PE
section at a 512-byte file boundary does not imply that its next RVA advances
by 512 bytes. A PE image normally uses a larger section alignment for RVAs.

Calling `region.file_align` closes physical output for the active region.
Begin another region before emitting more content.

### Compact Files Do Not Require Compact Addresses

Logical page separation does not require page-sized holes in the file.

For an ELF load segment, the loader requires:

```text
p_vaddr mod p_align = p_offset mod p_align
```

It does not require each `p_offset` to be page aligned. A direct writer can
therefore:

1. close the previous region with alignment `1`;
2. take the next FOA from `file_cursor_real()`;
3. advance the next virtual address beyond the previous logical end;
4. choose a virtual address with the same page remainder as the FOA.

This produces compact file bytes while preserving independent virtual pages.

Do not create page-sized physical padding merely because virtual addresses are
page separated. Physical padding is required only when the format or chosen
layout requires it.

### BSS Is a Logical Extent Without Payload

A pure BSS-style region contains reserve but no initialized bytes:

```asm
region.begin(".bss", 0x403000, file_cursor_real());

bss_start:
reserve(64);
bss_end:

region.file_align(1);

defer {
    assert(region_file_size(bss_start) == 0);
    assert(region_logical_size(bss_start) == 64);
}
```

The region occupies 64 bytes in the logical image and zero bytes in the file.

Each format records this differently:

- PE uses a nonzero virtual size and normally zero stored data for an
  uninitialized section.
- COFF records the section's storage size while keeping its raw-data pointer
  zero.
- ELF uses a larger memory size than file size for a load segment, or a
  `SHT_NOBITS` section where section headers are present.

The region model supplies the two independent sizes. The selected family helper
must encode them according to the target format.

### Continue Both Coordinate Systems After BSS

A BSS region advances the logical address but not the real file cursor. The
next file-backed region must therefore use two different continuation facts:

```text
next physical offset = previous real file cursor
next logical address = at least previous logical end
```

Using the real file cursor for both values makes the next region overlap BSS in
memory. Using the potential cursor for both values creates unnecessary file
padding.

For page-congruent ELF segments, the next logical address must also satisfy:

```text
next logical address mod page alignment
    = next physical offset mod page alignment
```

The direct source owns this calculation unless the selected helper explicitly
performs it.

Every region used with final region queries should have an unambiguous logical
range. Reusing the same logical origin for BSS and a following metadata region
can make an address identify the wrong region even when their file bytes do not
overlap.

### Capture Row Addresses and Row Offsets Separately

A generated table row can have both:

- a logical address used by `load.*` and `store.*`;
- a file offset written into format metadata or used for structural checks.

These values may happen to match in a zero-origin flat layout. Direct format
code must not rely on that coincidence.

This is incorrect when logical and physical coordinates differ:

```text
const row_foa = file_cursor_real()
emit.u32(0)

defer {
    store.u32(row_foa, value)
}
```

`store.u32` expects an address in XIRASM's logical output space, not a file
offset.

Capture both facts when both are needed:

```text
const row_address = here()
const row_foa = file_cursor_real()
emit.u32(0)

defer {
    store.u32(row_address, row_foa)
}
```

The same rule applies to section headers, program headers, symbol tables,
dynamic records, and generated metadata.

### Stable Region Facts

Final region facts are queried with an address inside the region:

| Query | Stable result |
|---|---|
| `region_file_offset(address)` | Physical base offset |
| `region_file_size(address)` | Materialized byte count |
| `region_logical_size(address)` | Complete logical extent |

These are stable-image queries. Use them in `defer` or in helpers that register
a deferred finalizer.

The address argument should normally be a label captured at region start:

```text
section_start:
    ...

defer {
    let raw_ptr = region_file_offset(section_start)
    let raw_size = region_file_size(section_start)
    let virtual_size = region_logical_size(section_start)
}
```

Passing an FOA as the address argument is incorrect. The query locates a region
by logical address.

### Reserve First, Then Backfill

Fields that depend on final layout must occupy their final width before payload
layout begins.

```asm
region.begin("header", 0, 0);

payload_foa_field:
emit.u32(0);
payload_file_size_field:
emit.u32(0);
payload_logical_size_field:
emit.u32(0);

region.file_align(1);

region.begin("payload", 0x1000, file_cursor_real());

payload_start:
emit.bytes(b"ABC");
reserve(5);
payload_end:

region.file_align(1);

defer {
    store.u32(payload_foa_field, region_file_offset(payload_start));
    store.u32(payload_file_size_field, region_file_size(payload_start));
    store.u32(payload_logical_size_field, region_logical_size(payload_start));
}
```

The final file contains:

```text
0c 00 00 00 03 00 00 00 08 00 00 00 41 42 43
```

The payload begins at FOA `12`, stores three bytes, and occupies eight logical
bytes.

This pattern is suitable for:

- PE section rows and data-directory entries;
- COFF section rows, symbol-table pointers, and relocation pointers;
- ELF program headers and section headers;
- custom size, offset, count, and checksum fields.

The finalizer changes values only. It does not insert the placeholders.

### `late_layout` and `defer` Are Different Phases

Direct format construction has two explicit delayed phases:

| Phase | May change layout | Typical work |
|---|---|---|
| `late_layout` | Yes | Append tables, copy virtual scratch data, create final regions |
| `defer` | No | Backfill fields, read bytes, compute checksums, assert invariants |

Use `late_layout` when real bytes do not exist until ordinary source has
finished registering sections, symbols, or relocations:

```asm
total_size:
emit.u32(0);

late_layout {
    emit.bytes(b"TAIL");
}

defer {
    store.u32(total_size, region_file_size(total_size));
}
```

Bytes appended by `late_layout` participate in final layout. The deferred
backfill observes the completed image.

Use `defer` when the storage already exists and only its value is late.

Do not use `defer` to:

- emit a missing table;
- begin or switch regions;
- create labels;
- reserve storage;
- align output;
- add instructions;
- change section or segment boundaries.

If a finalizer needs a field, row, or table, ordinary source or `late_layout`
must create that storage first.

### Virtual Scratch Data and Late Materialization

Virtual regions are useful when a table must be assembled, measured, or patched
before its bytes are placed in the file.

A typical direct workflow is:

1. build records in a virtual region;
2. retain their logical start and measured size;
3. enter `late_layout`;
4. begin the final file-backed table region;
5. copy the virtual bytes with `load.bytes`;
6. use `defer` for final header fields and validation.

Virtual bytes do not enter the output automatically. Copying them during
`late_layout` is an explicit materialization step.

This pattern is useful for symbol tables, relocation tables, string tables, and
section-header tables whose final order is chosen after payload emission.

### Finalizer Registration and Ownership

Deferred finalizers execute in registration order. Direct helpers often
register their own finalizers when called.

Order matters when one finalizer reads a field written by another. Keep the
dependency visible:

```text
register base-field patches
register directory and table patches
register checksum initialization
register checksum region accumulation
register checksum completion
register final assertions
```

Do not register two finalizers as owners of the same field unless the later
write is an intentional, documented override.

The safest ownership rule is:

```text
one field
one construction layer
one final writer
```

### Direct-Layout Checklist

Before using a direct family helper, verify:

1. Every label and `here()` value is treated as a logical address.
2. Every FOA comes from explicit layout math or `region_file_offset`.
3. Logical size and file size are written to the correct format fields.
4. Tail reserve is trimmed only when it represents file-free storage.
5. Middle reserve remains physical when initialized data follows it.
6. Every region is closed before the next file-backed region begins.
7. BSS advances the next logical address even when the real file cursor does
   not move.
8. ELF load addresses remain congruent with their physical offsets.
9. A row's logical address is captured separately from its FOA.
10. `late_layout` creates final bytes; `defer` only patches or validates them.
11. All backfill targets already exist in the physical image.
12. Each field has one clear owner.

Chapter 3 lists the additional counts, indexes, rows, alignments, and table
relationships that become the source's responsibility when it leaves the
ordinary facade.

## 3. Manual Responsibilities

Moving below the ordinary facade changes more than syntax. It transfers
ownership.

The ordinary facade accepts named declarations and derives the records needed
to represent them. Compatibility wrappers transfer part of that work to the
source. Direct family helpers transfer nearly all of it.

Before choosing a lower layer, identify every value that the source will now
own. A direct format is correct only when its independently emitted records
describe one coherent file.

### What the Ordinary Facade Normally Owns

The ordinary facade normally performs these tasks:

| Responsibility | Ordinary behavior |
|---|---|
| Record counts | Derives counts from declared sections, segments, and symbols |
| Row assignment | Assigns rows in declaration order |
| Name resolution | Resolves section and symbol names to numeric indexes |
| File placement | Advances physical regions and generated tables |
| Logical placement | Advances RVAs or virtual addresses independently |
| Table generation | Emits standard import, export, relocation, and dynamic data |
| Relationships | Connects directories, links, indexes, and target records |
| Backfill | Registers finalizers for fields that depend on stable layout |
| Validation | Rejects inconsistent declarations and unsupported combinations |

A direct helper may still derive one local fact. For example, an `_auto`
finalizer may read a region's final file size. It does not assume ownership of
the entire format plan.

The source still decides:

- which row is being patched;
- how many rows exist;
- what each index means;
- where related tables are located;
- which records refer to one another;
- when a table is complete;
- which finalizer owns each field.

### Freeze the Record Plan Before Emission

Most standard headers contain counts or offsets that describe records emitted
later. A direct source should establish a stable record plan before writing the
header.

A useful planning model is:

```text
file kind and machine
header variants and flags
ordered payload regions
ordered generated tables
ordered symbols
ordered relocations
entry point
directory and dynamic relationships
```

The plan does not need a special runtime object. It can be expressed through
constants, lists, maps, or carefully ordered source. What matters is that row
and index assignments stop changing after dependent records are emitted.

Do not assign indexes opportunistically while writing relocation or directory
records. Resolve ordering first, then emit references.

### Counts Must Describe Emitted Records

A count field is a contract between a header and the records that follow it.

Typical direct counts include:

| Format family | Count examples |
|---|---|
| PE | section count, export function count, export name count |
| COFF | section count, symbol count, relocations per section |
| ELF executable | program-header count |
| ELF object | section-header count, symbols, relocations |
| ELF shared object | program headers, section headers, dynamic symbols |

Count the records that are actually encoded, including required sentinel or
reserved records.

Examples:

- an ELF section-header count includes the null section row;
- an ELF symbol table commonly includes its undefined symbol;
- a COFF symbol count includes auxiliary symbol records when present;
- a PE export function count and name count may differ;
- relocation counts are local to the section or table that owns them.

Do not use the number of source declarations when one declaration expands into
multiple encoded records.

### Rows, Indexes, and Section Numbers Are Different Namespaces

The word "index" is not universal. A direct source may use several numeric
namespaces at the same time.

| Namespace | Typical meaning |
|---|---|
| Header row | Zero-based position in a generated table |
| Section number | Format-defined section identity |
| Section index | Position in a section-header table |
| Symbol index | Position in a symbol table |
| Relocation index | Position in a relocation table |
| Directory slot | Fixed PE data-directory kind |
| Dynamic row | Position in an ELF dynamic array |

These values are not interchangeable.

For example:

- a PE helper row selects a section-table slot;
- a COFF section row is zero-based, while a symbol's section number is
  normally one-based;
- ELF section index zero is reserved for the null section;
- an ELF relocation stores a symbol-table index, not a section-table row;
- a PE data-directory slot is a fixed semantic number, not an emitted row
  chosen by the source.

Use names that preserve the namespace:

```text
text_row
text_section_number
text_section_index
puts_symbol_index
rela_text_row
import_directory_slot
```

Avoid generic names such as `index` when several tables are active.

### Ordering Creates Numeric Identity

Rows and indexes derive meaning from ordering. Once another record refers to a
numeric position, changing the order changes the file's semantics.

Freeze these orders before dependent emission:

- PE section rows;
- PE exported-name ordering and ordinal relationships;
- PE relocation grouping by page;
- COFF section rows and symbol indexes;
- ELF program-header rows;
- ELF section indexes;
- ELF local and global symbol ordering;
- relocation rows and their target symbol indexes;
- dynamic strings and the offsets that refer to them.

If records must be sorted, sort the declarations before computing dependent
indexes and offsets.

Do not sort one table after another table has stored references into its old
order.

### Offsets Must Identify the Correct Physical Object

Direct helpers frequently accept explicit physical locations:

```text
section raw pointer
program-header file offset
symbol-table FOA
relocation-table FOA
section-header-table FOA
string-table FOA
dynamic-table FOA
```

Each offset must point to the first byte of the encoded object it describes.
The corresponding size must cover exactly the intended range.

Avoid deriving table offsets from a guessed record count when the table may
contain alignment, sentinels, auxiliary rows, or variable-length strings.

Prefer one of these sources:

- a real file cursor captured immediately before emission;
- `region_file_offset` after stable layout;
- a checked calculation from fixed-width records;
- a label pair for a measured byte range.

Do not use a logical label value as a physical file offset.

### Sizes Must Use the Correct Extent

Direct formats commonly expose several size meanings:

| Size | Includes |
|---|---|
| Logical size | Initialized bytes, middle gaps, and reserved tail |
| Physical size | Materialized bytes and physical file alignment |
| Record size | Bytes occupied by one encoded record |
| Table size | Complete encoded range of all table records |
| Image size | Final logical extent rounded by format rules |

Choose the size that matches the field.

Common mistakes include:

- writing logical BSS size into a physical file-size field;
- writing aligned physical size into a virtual-size field;
- excluding a required null record from a table size;
- using a symbol count where a byte size is required;
- using the end of the file instead of the end of the directory range.

When a field describes a range, define both its start and end. A named range is
easier to audit than a repeated arithmetic expression.

### Alignment Has Multiple Independent Meanings

There is no single "format alignment."

Direct construction may need:

| Alignment | Purpose |
|---|---|
| Record alignment | Natural placement of a table or encoded structure |
| File alignment | Physical padding between stored ranges |
| Logical alignment | RVA or virtual-address placement |
| Page congruence | Required relationship between ELF virtual and file offsets |
| ABI alignment | Runtime stack, data, or symbol requirements |

Applying the wrong alignment can produce a structurally plausible file with
incorrect loading behavior.

Examples:

- PE file alignment and section alignment are separate values;
- COFF table placement does not define a loaded virtual address;
- an ELF load segment may use a compact FOA while its virtual address advances
  to another page;
- a section's `addralign` field describes contained data, not necessarily the
  physical alignment of the section-header row.

Keep alignment names explicit:

```text
file_align
section_align
page_align
record_align
symbol_align
```

Do not reuse one variable merely because two values currently happen to match.

### Flags Must Agree with Content and Placement

Header flags, section characteristics, segment permissions, symbol binding,
and relocation types describe how consumers must interpret the bytes.

The direct source owns consistency between:

- code and executable permissions;
- mutable data and writable permissions;
- read-only metadata and nonwritable placement;
- BSS and uninitialized-data types;
- object machine type and relocation encoding;
- symbol binding and section assignment;
- executable type and addressing model.

Do not create a writable and executable region merely because code and dynamic
metadata were emitted together. Separate regions when their permissions differ.

Likewise, do not mark a section as file-backed initialized data when it contains
only reserved storage.

### Table Relationships Must Be Complete

Formats contain graphs of related tables, not isolated byte arrays.

Typical relationships include:

| Owner | Relationship |
|---|---|
| PE optional header | Data-directory slot points to a directory RVA and size |
| PE import descriptor | Names lookup and address tables plus a library name |
| PE export directory | Connects address, name-pointer, and ordinal tables |
| COFF section row | Connects raw data and the section's relocation table |
| COFF relocation | Connects a section-relative location to a symbol index |
| ELF section header | Uses `link` and `info` to identify related tables |
| ELF relocation | Connects an offset, symbol index, type, and optional addend |
| ELF dynamic array | Points to string, symbol, hash, relocation, and PLT data |

Emitting all participating tables is not sufficient. Their pointers, indexes,
counts, and sizes must describe the same relationships.

Document each relationship in source with paired names:

```text
dynsym_index and dynstr_index
rela_text_index and text_index
import_directory_start and import_directory_end
symbol_table_foa and symbol_count
```

This makes cross-table mistakes visible during review.

### Required Null and Sentinel Records Still Count as Layout

Many formats require terminators or reserved first records.

Common examples include:

- the null ELF section header;
- the undefined ELF symbol;
- a terminating ELF dynamic entry;
- null PE import descriptors and thunk entries;
- the minimum COFF string-table length field;
- padding relocation entries required by a block format.

These bytes are part of the physical layout even when they do not represent a
user declaration.

Decide whether each sentinel contributes to:

- a count;
- a table size;
- an index offset;
- a file alignment calculation;
- a consumer-visible termination rule.

Do not append a terminator after dependent offsets have already been frozen
unless that space was included in the original plan.

### Relocations Have Several Simultaneous Contracts

A relocation record must agree with:

1. the width and encoding of the field being relocated;
2. the address or section-relative offset of that field;
3. the target symbol index or runtime address;
4. the relocation type;
5. the addend convention;
6. the machine type;
7. the table or section that owns the relocation.

A correct numeric target with the wrong relocation type is still incorrect.
A correct type with the wrong symbol index is still incorrect.

Keep relocation declarations close to the field they describe, but assign
symbol indexes from the frozen symbol plan.

Do not apply a final absolute patch to a field that is intentionally left for a
linker or loader relocation. The encoded placeholder and relocation record are
one combined contract.

### Direct Imports and Exports Own Generated Names

Import and export tables contain more than addresses. They may also contain:

- library names;
- symbol names;
- aliases;
- hint/name records;
- lookup and address tables;
- name-pointer tables;
- ordinal tables;
- dynamic string offsets;
- symbol bindings;
- hash records;
- relocation entries.

A direct source must preserve the ordering assumptions used by every generated
offset.

If names are sorted, compute name indexes after sorting. If aliases are used,
distinguish the source symbol name, exported name, import slot name, and PLT
label.

Treat generated labels as part of the table plan. A duplicated label or
ambiguous alias can corrupt several dependent records at once.

### `_auto` Means Local Derivation

An `_auto` helper normally derives values available from one known region:

- physical file offset;
- physical size;
- logical size;
- entry displacement within a segment;
- a local record count from a measured range.

It does not generally derive:

- the number of unrelated sections or segments;
- global row ordering;
- symbol indexes across tables;
- cross-table `link` and `info` relationships;
- directory slot ownership;
- all generated metadata;
- final permission separation.

Read an `_auto` signature as:

```text
derive the local fields represented by this helper
```

Do not read it as:

```text
complete the entire executable format automatically
```

### Backfill Ownership Must Be Singular

Direct helpers often register deferred stores. The caller must know which
fields they patch.

Before combining helpers, record:

```text
field
placeholder address
writer helper
registration order
input facts
later readers
```

Two helpers may legitimately contribute to one logical structure while writing
different fields. They must not silently overwrite the same field.

Be especially careful when mixing:

- raw and `_auto` finalizers;
- a compatibility wrapper and its underlying direct helper;
- manual directory patches and directory-specific helpers;
- checksum helpers and later header writes;
- ordinary facade generation and direct table emission.

If field ownership is unclear, use one layer for the entire structure.

### A Safe Direct Construction Sequence

A direct format source is easier to reason about when it follows one visible
sequence:

1. Select the file kind, machine, width, and global options.
2. Freeze section, segment, symbol, relocation, and table ordering.
3. Assign every row, index, section number, and fixed directory slot.
4. Derive counts from the frozen record plan.
5. Emit headers and fixed-width placeholders.
6. Emit payload regions with separate logical and physical coordinates.
7. Close each region and preserve BSS semantics.
8. Emit or append generated tables in their planned order.
9. Register backfills for stable offsets, sizes, addresses, and relationships.
10. Register final structural assertions and checksums.
11. Verify the file with an independent consumer.

The exact order of steps 8 and 9 may vary because helper calls can register
finalizers before later tables exist. The ownership and final relationships
must remain explicit.

### Common Failure Patterns

| Symptom | Likely responsibility error |
|---|---|
| Header sees fewer records than emitted | Count frozen too early or sentinel omitted |
| Relocation targets the wrong name | Symbol ordering changed after index assignment |
| BSS consumes file bytes | Logical and physical sizes were conflated |
| Later region overlaps BSS | Logical progression followed the real file cursor |
| File contains page-sized zero holes | Virtual alignment was applied as file padding |
| Finalizer writes an unrelated range | FOA was used as a logical store address |
| Loader rejects a directory | RVA, size, or termination relationship is incomplete |
| Linker ignores a relocation | Wrong machine type, relocation type, or symbol index |
| Import call reaches bad memory | PLT, GOT, symbol, relocation, or dynamic rows disagree |
| Section appears writable and executable | Permission-separated content was combined |
| Checksum changes after completion | A later finalizer still modifies covered bytes |

These failures often survive superficial byte inspection. Direct formats must
be validated as relationships, not merely as recognizable signatures.

### Manual-Responsibility Checklist

Before entering a family-specific direct chapter, confirm:

1. The complete record order is known.
2. Every count includes required reserved and sentinel records.
3. Row, section-number, section-index, and symbol-index namespaces are distinct.
4. Every dependent index is assigned after its table order is frozen.
5. Every physical offset points to the intended encoded range.
6. Every size uses the correct logical, physical, record, or table extent.
7. File, logical, page, record, and ABI alignments are not conflated.
8. Flags match the content and permissions of their region.
9. All directory and table relationships are paired and measurable.
10. Every relocation matches its field encoding and target namespace.
11. Required null and sentinel records are present.
12. `_auto` helpers are treated as local derivation only.
13. Every deferred field has one final owner.
14. Finalizer registration order matches data dependencies.
15. No field is simultaneously owned by the ordinary facade and direct code.

Part II applies these rules to direct PE construction, beginning with headers
and section rows.

## Part II: Direct PE Construction

## 4. PE Headers and Section Rows

Direct PE construction begins with `format/pe.inc`.

This layer emits the DOS header, PE signature, file header, optional header,
data-directory array, and an exact number of empty section rows. The source
then creates each section region and registers finalizers for fields that
depend on its completed layout.

This chapter covers only:

- PE32 and PE32+ headers;
- EXE and DLL header variants;
- section rows;
- entry point and aggregate size fields;
- initialized and uninitialized sections.

Imports, exports, relocations, resources, and checksums are covered separately.

### Import the Direct PE Family

Use only the direct family include:

```text
import("format/pe.inc");
```

Do not import `format/format.inc`, `format/pe32.inc`, or `format/pe64.inc` in
the same construction workflow. Those layers can emit or finalize fields that
the direct source already owns.

### The Direct Header Sequence

A direct PE file starts with two calls:

| File kind | Begin call | Header call |
|---|---|---|
| PE32 EXE | `pe_begin32()` | `pe_headers32(section_count)` |
| PE32 DLL | `pe_begin_dll32()` | `pe_headers_dll32(section_count)` |
| PE32+ EXE | `pe_begin64()` | `pe_headers64(section_count)` |
| PE32+ DLL | `pe_begin_dll64()` | `pe_headers_dll64(section_count)` |

The begin call:

- sets the logical origin to the default image base;
- emits the DOS header and message;
- places the PE signature at file offset `0x80`.

The header call:

- emits the machine-specific file header;
- emits the PE32 or PE32+ optional header;
- emits sixteen zeroed data-directory entries;
- emits exactly `section_count` empty section rows;
- pads the complete header area to the default file alignment.

The section count must be final before the header is emitted.

### Default Direct Header Policy

The direct helpers use these default layout values:

| Property | PE32 | PE32+ |
|---|---:|---:|
| Image base | `0x00400000` | `0x0000000140000000` |
| File alignment | `0x200` | `0x200` |
| Section alignment | `0x1000` | `0x1000` |
| Subsystem | Console | Console |
| NX compatibility | Enabled | Enabled |
| Dynamic base | Disabled | Disabled |

Dynamic-base flags are not enabled by the basic direct header because this
chapter does not emit a base-relocation directory. Relocation and ASLR policy
belong to Chapter 6.

Use `pe_headers32_with_characteristics` or
`pe_headers64_with_characteristics` when the file-header characteristic bits
must differ from the standard EXE or DLL variants.

### Section Rows Are Zero-Based

Direct PE helpers use a zero-based section row:

```text
row 0 -> first section header
row 1 -> second section header
row 2 -> third section header
```

PE32 and PE32+ have different optional-header sizes, so they use different row
address helpers:

| Width | Row address helper |
|---|---|
| PE32 | `pe_row32_foa(row)` |
| PE32+ | `pe_row_foa(row)` |

The row number is not an RVA and not a file offset. It selects a 40-byte
section-header slot that already exists in the header.

### Simple RVA and Raw-Pointer Helpers

For small, regularly placed sections, `pe.inc` provides:

```text
pe_section_rva(row, section_align)
pe_section_raw_ptr(row, file_align)
```

With the defaults:

| Row | RVA | Raw pointer |
|---:|---:|---:|
| 0 | `0x1000` | `0x200` |
| 1 | `0x2000` | `0x400` |
| 2 | `0x3000` | `0x600` |

These helpers allocate one alignment slot per row. They are convenient when:

- every section fits within one section-alignment unit;
- every file-backed section fits within one file-alignment unit;
- BSS is last or unused raw slots are acceptable.

They are not general layout solvers.

A section larger than one alignment unit can overlap the convenience location
of the following row. A BSS section in the middle can leave an unused raw slot.
For compact or irregular layouts, calculate RVAs and raw pointers from the
previous completed section and use the `_at` section calls.

### Begin a Section Region

PE32+ uses:

```text
pe_begin_section(name, row, rva)
pe_begin_section_at(name, row, rva, raw_ptr)
```

PE32 uses:

```text
pe_begin_section32(name, row, rva)
pe_begin_section32_at(name, row, rva, raw_ptr)
```

The non-`_at` form derives the raw pointer from the row and default file
alignment. The `_at` form accepts an explicit raw pointer.

Both forms start a region whose:

- logical origin is `image_base + rva`;
- physical base is the chosen raw pointer.

The section name passed to the begin call names the XIRASM region. The
eight-byte section name written into the PE row is supplied separately to the
finalizer.

### Close File-Backed Sections with Physical Alignment

For region-derived finalization, close a file-backed section with:

```text
pe_align_section_file(row);
```

This closes the active region at the default `0x200` file alignment without
changing its logical size.

The distinction matters. A section containing fifteen code bytes has:

```text
VirtualSize      = 15
SizeOfRawData    = 512
PointerToRawData = section file offset
```

Use `pe_end_section(row, raw_size)` when the direct source intentionally
materializes an explicit raw size and will call the non-automatic section
finalizer with matching values.

Do not use ordinary logical `align` to replace PE file alignment. Logical
alignment changes section addresses and can make padding part of the virtual
size.

### Finalize a Section Row

The region-derived finalizers are:

```text
pe_finalize_section32_auto(row, name, start, characteristics)
pe_finalize_section64_auto(row, name, start, characteristics)
```

They derive:

| Section-row field | Source |
|---|---|
| Name | `name` argument |
| VirtualSize | `region_logical_size(start)` |
| VirtualAddress | section start minus image base |
| SizeOfRawData | `region_file_size(start)` |
| PointerToRawData | `region_file_offset(start)` when file size is nonzero |
| Characteristics | `characteristics` argument |

For a pure BSS section, the automatic finalizer writes:

```text
VirtualSize      = reserved logical size
SizeOfRawData    = 0
PointerToRawData = 0
```

The explicit finalizers are:

```text
pe_finalize_section32(row, name, rva, raw_ptr, start, end, characteristics)
pe_finalize_section64(row, name, rva, raw_ptr, start, end, characteristics)
```

Use them when the source already owns the RVA, raw pointer, and logical range.
The explicit form rounds `end - start` to the default file alignment for
`SizeOfRawData`. It is therefore intended for file-backed data, not pure BSS.

### Standard Section Names and Characteristics

`pe.inc` provides encoded eight-byte names:

```text
pe_name_text
pe_name_data
pe_name_rdata
pe_name_idata
pe_name_edata
pe_name_reloc
pe_name_rsrc
pe_name_bss
```

It also provides standard section characteristics:

| Constant | Intended content |
|---|---|
| `pe_text_chars` | Readable executable code |
| `pe_rdata_chars` | Read-only initialized data |
| `pe_data_chars` | Readable writable initialized data |
| `pe_bss_chars` | Readable writable uninitialized data |

The region name and encoded row name should describe the same section.

Custom names are limited to eight encoded bytes unless the source implements
another naming convention accepted by its consumer.

### Finalize Header Fields After Sections Exist

The direct header initially contains zero placeholders for layout-dependent
fields. Register the required finalizers after the corresponding ranges are
known.

Common calls are:

| Field | Helper |
|---|---|
| AddressOfEntryPoint | `pe_finalize_entry` |
| SizeOfImage | `pe_finalize_image_size` |
| SizeOfCode | `pe_finalize_code_size` |
| SizeOfInitializedData | `pe_finalize_init_data_size` |
| BaseOfCode | `pe_finalize_base_of_code` |
| PE32 BaseOfData | `pe_finalize_base_of_data32` |

`pe_finalize_entry(entry, section_start, section_rva)` writes:

```text
section_rva + (entry - section_start)
```

`pe_finalize_image_size` uses the last logical section range and rounds the
result to the default section alignment.

The direct helper currently exposes the uninitialized-data total through the
generic fixed-width finalizer:

```text
pe_finalize_u32(
    image_base + pe_opt_size_of_uninit_data_foa,
    uninitialized_size
)
```

When several BSS sections exist, sum their logical sizes before registering
that field.

### Complete PE32+ Example

This example creates three section rows:

- `.text` contains the entry point;
- `.rdata` contains a read-only value;
- `.bss` reserves writable memory without file payload.

```asm
import("format/pe.inc");

const section_count: u16 = 3
const text_row: u64 = 0
const rdata_row: u64 = 1
const bss_row: u64 = 2

const text_rva: u64 = pe_section_rva(text_row, pe_default_section_align)
const rdata_rva: u64 = pe_section_rva(rdata_row, pe_default_section_align)
const bss_rva: u64 = pe_section_rva(bss_row, pe_default_section_align)

pe_begin64();
pe_headers64(section_count);

pe_begin_section(".text", text_row, text_rva);
text_start:
entry:
    mov eax, [rel rdata_start]
    mov [rel bss_start], eax
    xor eax, eax
    ret
text_end:
pe_align_section_file(text_row);

pe_begin_section(".rdata", rdata_row, rdata_rva);
rdata_start:
dd(42);
rdata_end:
pe_align_section_file(rdata_row);

pe_begin_section(".bss", bss_row, bss_rva);
bss_start:
reserve(64);
bss_end:
pe_align_section_file(bss_row);

pe_finalize_section64_auto(
    text_row,
    pe_name_text,
    text_start,
    pe_text_chars
);
pe_finalize_section64_auto(
    rdata_row,
    pe_name_rdata,
    rdata_start,
    pe_rdata_chars
);
pe_finalize_section64_auto(
    bss_row,
    pe_name_bss,
    bss_start,
    pe_bss_chars
);

pe_finalize_entry(entry, text_start, text_rva);
pe_finalize_image_size(bss_rva, bss_start, bss_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_init_data_size(rdata_start, rdata_end);
pe_finalize_base_of_code(text_rva);
pe_finalize_u32(
    pe_default_image_base64 + pe_opt_size_of_uninit_data_foa,
    bss_end - bss_start
);
```

The entry reads the read-only value, writes it into BSS, returns zero, and
requires no import table.

### Complete PE32 Example

PE32 uses the same section plan with width-specific begin and row finalizers:

```asm
import("format/pe.inc");

x86.use32();

const section_count: u16 = 3
const text_row: u64 = 0
const rdata_row: u64 = 1
const bss_row: u64 = 2

const text_rva: u64 = pe_section_rva(text_row, pe_default_section_align)
const rdata_rva: u64 = pe_section_rva(rdata_row, pe_default_section_align)
const bss_rva: u64 = pe_section_rva(bss_row, pe_default_section_align)

pe_begin32();
pe_headers32(section_count);

pe_begin_section32(".text", text_row, text_rva);
text_start:
entry:
    mov eax, [rdata_start]
    mov [bss_start], eax
    xor eax, eax
    ret
text_end:
pe_align_section_file(text_row);

pe_begin_section32(".rdata", rdata_row, rdata_rva);
rdata_start:
dd(42);
rdata_end:
pe_align_section_file(rdata_row);

pe_begin_section32(".bss", bss_row, bss_rva);
bss_start:
reserve(64);
bss_end:
pe_align_section_file(bss_row);

pe_finalize_section32_auto(
    text_row,
    pe_name_text,
    text_start,
    pe_text_chars
);
pe_finalize_section32_auto(
    rdata_row,
    pe_name_rdata,
    rdata_start,
    pe_rdata_chars
);
pe_finalize_section32_auto(
    bss_row,
    pe_name_bss,
    bss_start,
    pe_bss_chars
);

pe_finalize_entry(entry, text_start, text_rva);
pe_finalize_image_size(bss_rva, bss_start, bss_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_init_data_size(rdata_start, rdata_end);
pe_finalize_base_of_code(text_rva);
pe_finalize_base_of_data32(rdata_rva);
pe_finalize_u32(
    pe_default_image_base32 + pe_opt_size_of_uninit_data_foa,
    bss_end - bss_start
);
```

PE32 uses absolute 32-bit addresses for the two data references. The basic
direct header uses the fixed default image base and does not advertise dynamic
rebasing.

### Resulting Three-Section Layout

Both examples produce this section plan:

| Row | Name | RVA | Raw pointer | Raw size | Logical role |
|---:|---|---:|---:|---:|---|
| 0 | `.text` | `0x1000` | `0x200` | `0x200` | Code and entry |
| 1 | `.rdata` | `0x2000` | `0x400` | `0x200` | Read-only data |
| 2 | `.bss` | `0x3000` | `0` | `0` | 64 bytes of memory |

The complete file size is `0x600`, or 1536 bytes. BSS increases
`SizeOfImage` to `0x4000` without increasing the file size.

The width-specific header fields differ:

| Field | PE32 | PE32+ |
|---|---:|---:|
| Machine | `0x014c` | `0x8664` |
| Optional-header magic | `0x010b` | `0x020b` |
| Default image base | `0x00400000` | `0x0000000140000000` |
| BaseOfData | Present | Not present |

The section-row semantics remain the same.

### Use `_at` for Irregular Physical Layouts

The default raw-pointer helper reserves one `0x200` slot for every row. Use the
explicit `_at` begin calls when:

- a section's raw data exceeds one file-alignment unit;
- BSS appears before another file-backed section;
- sections are reordered physically;
- metadata is placed outside row order;
- the file uses a deliberate nondefault raw layout.

A compact direct layout should derive the next raw pointer from the previous
file-backed region's real end, then pass it explicitly:

```text
next_raw_ptr = aligned previous physical end
pe_begin_section_at(name, row, rva, next_raw_ptr)
```

The section row remains in logical table order even when its payload is placed
through an explicit raw pointer.

### Direct PE Header Checklist

Before adding directories or relocations, confirm:

1. `section_count` equals the number of emitted section rows.
2. PE32 source selects `x86.use32()`.
3. Every row number is unique and within the declared count.
4. Every RVA is aligned and follows the previous logical extent.
5. Every file-backed raw pointer is aligned and does not overlap another range.
6. File-backed regions close with the intended physical alignment.
7. BSS has nonzero virtual size, zero raw size, and zero raw pointer.
8. Section names and characteristics match their content.
9. Entry RVA identifies executable code.
10. SizeOfCode and SizeOfInitializedData use physical sizes.
11. SizeOfUninitializedData uses logical BSS sizes.
12. SizeOfImage follows the last logical section and section alignment.
13. PE32 BaseOfData identifies the first data RVA.
14. Dynamic-base flags remain disabled until relocations are present.
15. Each header field has one finalizer owner.

Chapter 5 builds PE import, export, and data-directory relationships on top of
these stable headers and section rows.

## 5. PE Imports, Exports, and Directories

A PE data directory connects one optional-header slot to a table or range
elsewhere in the image. The section row describes where the containing bytes
are loaded. The directory entry identifies the specific structure inside that
section.

Direct construction therefore has two separate tasks:

1. emit and finalize the section that contains the metadata;
2. write the matching directory RVA and size into the optional header.

The import and export helpers build their table families, but the direct caller
still chooses section rows, section placement, permissions, aggregate header
sizes, and the directory finalizers.

### Import the Most Specific Direct Helper

Use the direct extension file that owns the table being constructed:

```text
import("format/pe_import.inc");
import("format/pe_export.inc");
```

Each extension makes the base declarations from `pe.inc` available. Importing
both files is sufficient for a DLL that has both imports and exports.

These files are direct family helpers. They do not create an ordinary format
plan, choose section rows, or finish the image automatically.

### The Data-Directory Table

PE32 and PE32+ optional headers each reserve 16 directory entries. Every normal
entry contains:

```text
u32 address
u32 size
```

For most entries, `address` is an RVA. The section's raw pointer is not written
into the directory table.

The direct row-address helpers differ by optional-header width:

| Header | Directory RVA field | Directory size field |
|---|---|---|
| PE32 | `pe_dir32_rva_foa(slot)` | `pe_dir32_size_foa(slot)` |
| PE32+ | `pe_dir_rva_foa(slot)` | `pe_dir_size_foa(slot)` |

The most common slots in this chapter are:

| Slot | Constant | Meaning |
|---:|---|---|
| 0 | `pe_dir_export` | Export directory |
| 1 | `pe_dir_import` | Import descriptors |
| 12 | `pe_dir_iat` | Optional IAT range |

The generic finalizers write a caller-supplied address and size:

```text
pe_finalize_data_dir32(slot, rva, size)
pe_finalize_data_dir64(slot, rva, size)
```

Use them when a direct layout already has the exact range. The import and export
helpers also provide specialized finalizers that derive the directory RVA from
the containing section:

```text
pe_finalize_import_dir32(idata_rva, idata_start, directory_start, directory_end)
pe_finalize_import_dir64(idata_rva, idata_start, directory_start, directory_end)

pe_finalize_export_dir32(edata_rva, edata_start, directory_start, directory_end)
pe_finalize_export_dir64(edata_rva, edata_start, directory_start, directory_end)
```

The conversion is:

```text
directory RVA = section RVA + (directory address - section start)
directory size = directory end - directory start
```

The directory labels and section start are logical addresses. No FOA belongs
in this calculation.

The certificate-table entry at `pe_dir_security` is exceptional in the PE
format: its address field is a file offset rather than an RVA. Do not apply the
normal RVA formula to that slot.

### Direct Import Declarations

An import set is a map grouped by DLL name. Prefer the grouped declarations for
ordinary batches:

```asm
let imports: map = pe_import_new()
imports = pe_import_use64_many(
    imports,
    "KERNEL32.DLL",
    list.of("ExitProcess", "VirtualAlloc")
)
imports = pe_import_use64_pairs(
    imports,
    "ADVAPI32.DLL",
    list.of("close_key", "RegCloseKey")
)
```

`*_many` uses matching local slot and imported-name labels. `*_pairs` accepts
alternating slot/name strings. Each call returns the updated map, so keep the
assignment when adding another group.

The declaration functions are:

| Form | Meaning |
|---|---|
| `pe_import_use32_many` / `pe_import_use64_many` | Add matching-name batches |
| `pe_import_use32_pairs` / `pe_import_use64_pairs` | Add explicit slot/name batches |
| `pe_import_use32` | Named PE32 import; slot label equals function name |
| `pe_import_use64` | Named PE32+ import; slot label equals function name |
| `pe_import_use32_as` | Named PE32 import with an explicit slot label |
| `pe_import_use64_as` | Named PE32+ import with an explicit slot label |
| `pe_import_use32_ordinal_as` | PE32 ordinal import with an explicit slot |
| `pe_import_use64_ordinal_as` | PE32+ ordinal import with an explicit slot |

The `_as` forms are useful when the imported name is inconvenient as a source
label:

```text
imports = pe_import_use64_as(
    imports,
    "KERNEL32.DLL",
    "GetCurrentProcessId",
    "get_current_process_id_iat"
)
```

The slot name becomes the label placed at the corresponding IAT entry. It is
the address used by an indirect call or load.

Duplicate declarations with the same slot and same target are idempotent.
Reusing a slot for a different name or ordinal is rejected.

### What `pe_import_emit32/64` Writes

Place the import emitter inside the chosen `.idata` region:

```text
idata_start:
pe_import_emit64(imports, idata_rva, idata_start);
idata_end:
```

The helper writes:

1. hint/name records for named imports;
2. null-terminated DLL names;
3. import lookup tables;
4. import address tables;
5. one descriptor per DLL;
6. a final null descriptor.

The width-specific emitter controls thunk width and the high-bit ordinal flag:

| Image | Emitter | Thunk width |
|---|---|---:|
| PE32 | `pe_import_emit32` | 4 bytes |
| PE32+ | `pe_import_emit64` | 8 bytes |

The helper defines stable labels for the descriptor range:

```text
pe_import_descriptors
pe_import_descriptors_end
```

Those labels are passed to the specialized import-directory finalizer. The
directory size covers the descriptor array, including the null descriptor. It
does not claim that every byte in `.idata` is part of the descriptor array.

The loader rewrites IAT entries, so a conventional `.idata` row uses
`pe_idata_chars`, which is initialized, readable, and writable but not
executable.

### Calling Through the IAT

PE32 and PE32+ use different instruction-address forms.

For PE32, `FF /2` can contain the absolute virtual address of the IAT slot:

```text
call_exit_process:
    db(0xff, 0x15);
    dd(0);

pe_finalize_u32(call_exit_process + 2, exit_process_iat);
```

For PE32+, the same encoding uses a signed RIP-relative displacement:

```text
call_exit_process:
    db(0xff, 0x15);
    dd(0);

pe_finalize_u32(
    call_exit_process + 2,
    exit_process_iat - (call_exit_process + 6)
);
```

The finalizer writes the operand field after the IAT slot address is stable.
It does not create a relocation record. Chapter 6 covers image rebasing and
base relocations.

### Complete PE32+ Importing Executable

This executable imports `ExitProcess`, passes an exit code of zero, and calls
the resolved IAT entry:

```asm
import("format/pe_import.inc");

let imports: map = pe_import_new()
imports = pe_import_use64_as(
    imports,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process_iat"
)

const text_row: u64 = 0
const idata_row: u64 = 1
const text_rva: u64 = pe_section_rva(text_row, pe_default_section_align)
const idata_rva: u64 = pe_section_rva(idata_row, pe_default_section_align)

pe_begin64();
pe_headers64(2);

pe_begin_section(".text", text_row, text_rva);
text_start:
entry:
    sub rsp, 40
    xor ecx, ecx
call_exit_process:
    db(0xff, 0x15);
    dd(0);
text_end:
pe_align_section_file(text_row);

pe_begin_section(".idata", idata_row, idata_rva);
idata_start:
pe_import_emit64(imports, idata_rva, idata_start);
idata_end:
pe_align_section_file(idata_row);

pe_finalize_section64_auto(
    text_row,
    pe_name_text,
    text_start,
    pe_text_chars
);
pe_finalize_section64_auto(
    idata_row,
    pe_name_idata,
    idata_start,
    pe_idata_chars
);

pe_finalize_entry(entry, text_start, text_rva);
pe_finalize_image_size(idata_rva, idata_start, idata_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_init_data_size(idata_start, idata_end);
pe_finalize_base_of_code(text_rva);
pe_finalize_import_dir64(
    idata_rva,
    idata_start,
    pe_import_descriptors,
    pe_import_descriptors_end
);
pe_finalize_u32(
    call_exit_process + 2,
    exit_process_iat - (call_exit_process + 6)
);
```

The resulting image has two sections:

| Row | Name | RVA | Raw pointer | Permissions |
|---:|---|---:|---:|---|
| 0 | `.text` | `0x1000` | `0x200` | Read, execute |
| 1 | `.idata` | `0x2000` | `0x400` | Read, write |

The file is 1536 bytes. The import directory points into `.idata`; the entry
point remains in `.text`.

### PE32 Import Differences

The PE32 workflow is structurally identical, with these substitutions:

| PE32+ | PE32 |
|---|---|
| `pe_import_use64_as` | `pe_import_use32_as` |
| `pe_begin64` | `pe_begin32` |
| `pe_headers64` | `pe_headers32` |
| `pe_begin_section` | `pe_begin_section32` |
| `pe_import_emit64` | `pe_import_emit32` |
| `pe_finalize_section64_auto` | `pe_finalize_section32_auto` |
| `pe_finalize_import_dir64` | `pe_finalize_import_dir32` |

PE32 source also selects `x86.use32()` and normally finalizes BaseOfData to the
first data section:

```text
pe_finalize_base_of_data32(idata_rva);
```

The indirect operand contains the absolute IAT address rather than a
RIP-relative displacement.

### Direct Export Declarations

An export set can be declared as a group. Use `many` when each target label is
also the public name, or `pairs` when the names differ:

```asm
let exports: list = pe_export_new()
exports = pe_export_use64_pairs(
    exports,
    list.of(
        "xir_add7", "xir_add7",
        "xir_sub3", "xir_sub3"
    )
)
```

The grouped forms are `pe_export_use32_many`, `pe_export_use32_pairs`,
`pe_export_use64_many`, and `pe_export_use64_pairs`. The existing single-item
forms remain useful when a declaration must be interleaved with other layout
logic.

Each declaration pairs:

```text
target label
public export name
```

The width-specific declaration names are:

```text
pe_export_use32
pe_export_use64
```

The current direct export emitter creates named exports. It assigns ordinal
base 1, sorts public names by emitted byte order, and builds matching address,
name-pointer, and ordinal tables. Direct callers do not manually sort the
names.

The emitter does not currently construct forwarded exports or ordinal-only
exports. Those layouts require direct record construction beyond this helper.

### What `pe_export_emit32/64` Writes

Place the emitter inside a read-only `.edata` region:

```text
edata_start:
pe_export_emit64(exports, "advanced_pe64.dll", edata_rva, edata_start);
edata_end:
```

The helper writes:

1. `IMAGE_EXPORT_DIRECTORY`;
2. the DLL name;
3. the export address table;
4. the ordinal table;
5. the sorted export names;
6. the name-pointer table.

It defines:

```text
pe_export_directory
pe_export_directory_end
```

The specialized export-directory finalizer uses those labels to register the
complete emitted range:

```text
pe_finalize_export_dir64(
    edata_rva,
    edata_start,
    pe_export_directory,
    pe_export_directory_end
)
```

The address table stores target RVAs. Exported code labels must therefore
belong to the same fixed image-base model used by the PE header.

### A DLL May Have No Entry Point

A DLL that requires no process-attach initialization may leave
AddressOfEntryPoint as zero. In that case:

- use `pe_begin_dll32/64` and `pe_headers_dll32/64`;
- emit and export callable functions;
- do not register `pe_finalize_entry`.

The loader still resolves imports and makes exports available. Chapter 6 adds
relocations when the DLL must load away from its preferred base.

### Complete PE32+ DLL with Imports and Exports

This DLL imports `GetCurrentProcessId` and exports three functions. One export
calls the imported API through the IAT:

```asm
import("format/pe_import.inc");
import("format/pe_export.inc");

let imports: map = pe_import_new()
imports = pe_import_use64_as(
    imports,
    "KERNEL32.DLL",
    "GetCurrentProcessId",
    "get_current_process_id_iat"
)

let exports: list = pe_export_new()
exports = pe_export_use64(
    exports,
    "xir_add7",
    "xir_add7"
)
exports = pe_export_use64(
    exports,
    "xir_sub3",
    "xir_sub3"
)
exports = pe_export_use64(
    exports,
    "xir_process_id",
    "xir_process_id"
)

const text_row: u64 = 0
const idata_row: u64 = 1
const edata_row: u64 = 2
const text_rva: u64 = pe_section_rva(text_row, pe_default_section_align)
const idata_rva: u64 = pe_section_rva(idata_row, pe_default_section_align)
const edata_rva: u64 = pe_section_rva(edata_row, pe_default_section_align)

pe_begin_dll64();
pe_headers_dll64(3);

pe_begin_section(".text", text_row, text_rva);
text_start:
xir_add7:
    mov eax, 7
    ret
xir_sub3:
    mov eax, 3
    ret
xir_process_id:
    sub rsp, 40
call_get_process_id:
    db(0xff, 0x15);
    dd(0);
    add rsp, 40
    ret
text_end:
pe_align_section_file(text_row);

pe_begin_section(".idata", idata_row, idata_rva);
idata_start:
pe_import_emit64(imports, idata_rva, idata_start);
idata_end:
pe_align_section_file(idata_row);

pe_begin_section(".edata", edata_row, edata_rva);
edata_start:
pe_export_emit64(
    exports,
    "advanced_pe64.dll",
    edata_rva,
    edata_start
);
edata_end:
pe_align_section_file(edata_row);

pe_finalize_section64_auto(
    text_row,
    pe_name_text,
    text_start,
    pe_text_chars
);
pe_finalize_section64_auto(
    idata_row,
    pe_name_idata,
    idata_start,
    pe_idata_chars
);
pe_finalize_section64_auto(
    edata_row,
    pe_name_edata,
    edata_start,
    pe_edata_chars
);

pe_finalize_image_size(edata_rva, edata_start, edata_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_base_of_code(text_rva);
pe_finalize_import_dir64(
    idata_rva,
    idata_start,
    pe_import_descriptors,
    pe_import_descriptors_end
);
pe_finalize_export_dir64(
    edata_rva,
    edata_start,
    pe_export_directory,
    pe_export_directory_end
);
pe_finalize_u32(
    call_get_process_id + 2,
    get_current_process_id_iat - (call_get_process_id + 6)
);

defer {
    store.u32(
        region_base() + pe_opt_size_of_init_data_foa,
        region_file_size(idata_start) + region_file_size(edata_start)
    );
}
```

Two initialized-data sections contribute to SizeOfInitializedData. The direct
caller therefore owns the aggregate and writes the sum after both regions are
stable.

The resulting DLL has:

| Row | Name | RVA | Raw pointer | Permissions |
|---:|---|---:|---:|---|
| 0 | `.text` | `0x1000` | `0x200` | Read, execute |
| 1 | `.idata` | `0x2000` | `0x400` | Read, write |
| 2 | `.edata` | `0x3000` | `0x600` | Read |

The file is 2048 bytes. The import directory contains one live descriptor and
one null descriptor. The export directory covers 128 bytes and publishes:

```text
xir_add7
xir_process_id
xir_sub3
```

The names appear in sorted order regardless of declaration order.

### Consuming the DLL from C

The exported routines use no arguments and return an integer, so a native
consumer can load and call them through the operating-system loader:

```c
#include <windows.h>

typedef int (__cdecl *no_arg_int)(void);

int main(void) {
    HMODULE module = LoadLibraryA("advanced_pe64.dll");
    if (module == NULL) {
        return 1;
    }

    no_arg_int add7 =
        (no_arg_int)(void *)GetProcAddress(module, "xir_add7");
    no_arg_int sub3 =
        (no_arg_int)(void *)GetProcAddress(module, "xir_sub3");
    no_arg_int process_id =
        (no_arg_int)(void *)GetProcAddress(module, "xir_process_id");

    int result = 0;
    if (add7 == NULL || sub3 == NULL || process_id == NULL) {
        result = 2;
    } else if (add7() != 7 || sub3() != 3) {
        result = 3;
    } else if ((DWORD)process_id() != GetCurrentProcessId()) {
        result = 4;
    }

    FreeLibrary(module);
    return result;
}
```

Successful loading proves that the import descriptor, lookup table, IAT, DLL
name, and section permissions satisfy the loader. Successful calls prove that
the export address, name-pointer, and ordinal tables agree with one another.

### Direct Directory Ownership

The direct layer assigns one owner to each directory entry:

| Directory | Typical owner |
|---|---|
| Import | `pe_finalize_import_dir32/64` |
| Export | `pe_finalize_export_dir32/64` |
| Resource | Resource helper and Chapter 6 finalizer |
| Base relocation | Relocation helper and Chapter 6 finalizer |
| IAT | Caller, when an explicit IAT directory entry is desired |
| Custom directory | `pe_finalize_data_dir32/64` |

Do not register two finalizers for the same slot. A generic finalizer should
not overwrite a specialized import or export finalizer later in registration
order.

### Direct Import and Export Checklist

Before accepting a direct PE image with imports or exports, confirm:

1. `.idata` and `.edata` have distinct section rows.
2. The declared header section count includes both metadata sections.
3. `.idata` is readable and writable, but not executable.
4. `.edata` is readable, but not writable or executable.
5. The import emitter width matches PE32 or PE32+.
6. Every import slot label is unique.
7. Ordinal imports remain within 16 bits.
8. The import directory points to the descriptor array.
9. The descriptor array ends with a null descriptor.
10. Every descriptor contains valid lookup-table, DLL-name, and IAT RVAs.
11. Indirect calls use the correct PE32 or PE32+ addressing form.
12. Every export target label belongs to the image.
13. Export names are unique.
14. The export directory covers the complete emitted export range.
15. The PE file header carries the DLL characteristic for DLL images.
16. A zero DLL entry point is deliberate, not an omitted initialization hook.
17. SizeOfInitializedData includes all file-backed metadata sections.
18. Each data-directory slot has one finalizer owner.
19. No directory RVA is confused with a raw pointer.
20. Fixed-base images do not advertise dynamic rebasing without relocations.

Chapter 6 adds base relocations, resources, checksums, and the header flags
that make rebasing an explicit loader contract.

## 6. PE Relocations, Resources, and Checksums

A direct PE image may contain valid code and section rows yet still be
incomplete as a loader contract. Three features commonly expose that gap:

- base relocations describe absolute image addresses that must move with the
  image;
- resources describe typed data through a directory tree rooted in `.rsrc`;
- the PE checksum covers the final physical file after every backfill.

These features use different coordinate systems and different finalization
rules. A relocation identifies an RVA inside the loaded image. A resource data
entry stores an RVA but is physically located inside `.rsrc`. A checksum reads
the final file bytes in FOA order.

The direct layer leaves those relationships visible. It provides record
emitters and finalizers, but the caller still owns section rows, section
placement, directory ownership, feature flags, and finalizer order.

### Import the Direct Extensions

Base relocations and resources are separate direct extensions:

```asm
import("format/pe_resource.inc");
import("format/pe_reloc.inc");
```

Both extensions load the common direct PE definitions. Do not import a
width-specific compatibility wrapper into the same example.

The relocation extension provides:

- relocation-list construction;
- `HIGHLOW` records for PE32;
- `DIR64` records for PE32+;
- page grouping and block padding;
- sorted-record validation.

The resource extension provides:

- direct resource-directory records;
- a compact single-numeric-resource helper;
- compiled resource-file ingestion;
- resource-tree sorting and grouping.

Checksum helpers remain in the common direct PE layer because they operate on
the complete physical file rather than one metadata section.

### Base Relocations Describe Stored Absolute Addresses

Position-independent instruction operands do not need PE base relocations.
For example, a PE32+ RIP-relative load remains valid when the image moves.

A stored absolute image address is different:

```text
preferred image:
    slot value = preferred base + target RVA

relocated image:
    slot value = actual base + target RVA
```

The loader must add the image-base delta to the stored value. The relocation
directory tells it which slots require that adjustment.

The width-specific relocation types are:

| Image | Stored value | Relocation type |
|---|---:|---|
| PE32 | 32-bit absolute image address | `pe_reloc_highlow` |
| PE32+ | 64-bit absolute image address | `pe_reloc_dir64` |

The helper names mirror that distinction:

| PE32 | PE32+ |
|---|---|
| `pe_reloc_add_highlow_at` | `pe_reloc_add_dir64_at` |
| `store.u32` | `store.u64` |
| `dd(0)` placeholder | `dq(0)` placeholder |

The `_at` helpers derive the relocation RVA from three facts:

1. the containing section RVA;
2. the slot's logical address;
3. the section's logical start.

The slot itself should be emitted as a zero placeholder. Write its final
absolute address from a stable-image finalizer. This avoids capturing an
address before all instruction sizes and region facts are stable.

### Relocation Blocks Are Grouped by Page

PE base relocation blocks use 4 KiB page RVAs. Every 16-bit entry combines:

- a four-bit relocation type;
- a twelve-bit offset within the page.

The direct grouped emitter expects relocation records in ascending RVA order:

```text
pe_reloc_assert_sorted(relocations)
pe_reloc_emit_grouped_sorted(relocations)
```

The emitter creates one block per referenced page. Each block contains:

1. the page RVA;
2. the block size;
3. the type-and-offset entries;
4. an `ABSOLUTE` entry when padding is required.

The relocation data directory must cover the emitted block range, not the
entire padded `.reloc` section:

```text
pe_reloc_grouped_start
pe_reloc_grouped_end
```

Use `pe_finalize_reloc_dir32` or `pe_finalize_reloc_dir64` to connect that
range to the base-relocation directory slot.

### Relocations and Header Flags Form One Contract

A relocation directory does not by itself advertise a relocatable image.
The optional header must also carry the appropriate DLL characteristics.

For PE32:

```text
pe_dll_dynamic_base | pe_dll_nx_compat
```

For PE32+:

```text
pe_dll_high_entropy_va | pe_dll_dynamic_base | pe_dll_nx_compat
```

`DYNAMIC_BASE` says that rebasing is supported. `HIGH_ENTROPY_VA` is the
PE32+ high-address policy. `NX_COMPAT` states that writable data need not be
executable.

Do not set `DYNAMIC_BASE` on an image whose absolute image addresses lack
relocation records. Conversely, do not emit relocation records for values
that are section-relative, file-relative, or already position-independent.

### Resource Trees Use Relative Directory Offsets

The PE resource directory is a three-level tree:

```text
type
  -> name or numeric id
       -> language
            -> data entry
```

Directory links inside the tree are offsets relative to the resource root.
The final data entry contains an image RVA and a byte size for the payload.

The compact helper creates one numeric path:

```text
numeric type -> numeric id -> numeric language -> payload
```

Call `pe_resource_emit_single_numeric` before the payload, then call
`pe_resource_finish_single_numeric` after the payload:

```text
pe_resource_emit_single_numeric(type, id, language)
emit payload bytes
pe_resource_finish_single_numeric(rsrc_rva, rsrc_start, payload_end, codepage)
```

The emitter defines the resource-root and data-entry labels. The finishing
helper backfills the payload RVA, payload size, codepage, and reserved field.

The resource data directory should cover:

```text
pe_resource_root
pe_resource_end
```

Use `pe_finalize_resource_dir32` or `pe_finalize_resource_dir64` to connect the
range to the resource directory slot.

For a complete compiled resource file, use
`pe_resource_emit_from_res(path, rsrc_rva)`. It reads the records, sorts the
type/name/language keys, emits the directory tree, and places the payloads
after the metadata. The direct caller still owns `.rsrc` placement, section
characteristics, and the PE data-directory finalizer.

### Checksums Must Run Last

The PE checksum is calculated over physical file bytes. It is not a hash, a
signature, or an integrity boundary. It is a folded word sum with the checksum
field treated as zero, followed by the final file size.

The direct checksum helpers divide the work by physical region:

| Helper | Responsibility |
|---|---|
| `pe_checksum_begin` | Clear the checksum field and fold the header region |
| `pe_checksum_add_region` | Fold one file-backed region |
| `pe_checksum_finish` | Add final file size and store the checksum |

Register them in final FOA order:

```text
header
.text
.data
.rsrc
.reloc
```

More importantly, register the checksum helpers after all finalizers that
change covered bytes. Section rows, directory entries, absolute pointer
backfills, image flags, and size aggregates must already be registered.

The correct sequence is:

```text
register structural backfills
register pointer and flag backfills
register checksum begin
register checksum region folds in FOA order
register checksum finish
```

A checksum registered too early describes an intermediate image.

### Header Size Must Include Every Section Row

Four PE32+ section rows do not fit in a `0x200`-byte header:

```text
section table start + four rows > 0x200
```

The direct header helpers align the complete header and section table to
`FileAlignment` and write the result to `SizeOfHeaders`.

When explicit raw placement is required, calculate the same value and use the
`_at` section begin helpers:

```text
headers_size =
    align_up(section_table_foa + section_count * 40, file_alignment)
```

The first raw section starts at `headers_size`, not at a permanently assumed
`0x200`. Subsequent raw pointers advance by each section's physical extent.

The complete example below uses four `0x200`-byte raw slots:

| Row | Section | RVA | Raw pointer |
|---:|---|---:|---:|
| 0 | `.text` | `0x1000` | `0x400` |
| 1 | `.data` | `0x2000` | `0x600` |
| 2 | `.rsrc` | `0x3000` | `0x800` |
| 3 | `.reloc` | `0x4000` | `0xa00` |

### Complete PE32+ DLL

This DLL contains:

- a minimal initialization entry;
- three absolute pointer slots;
- three `DIR64` relocation entries;
- one numeric `RCDATA` resource;
- a final PE checksum.

```asm
import("format/pe_resource.inc");
import("format/pe_reloc.inc");

const section_count: u16 = 4
const text_row: u64 = 0
const data_row: u64 = 1
const rsrc_row: u64 = 2
const reloc_row: u64 = 3

const text_rva: u64 = pe_section_rva(
    text_row,
    pe_default_section_align
)
const data_rva: u64 = pe_section_rva(
    data_row,
    pe_default_section_align
)
const rsrc_rva: u64 = pe_section_rva(
    rsrc_row,
    pe_default_section_align
)
const reloc_rva: u64 = pe_section_rva(
    reloc_row,
    pe_default_section_align
)
const resource_type_rcdata: u64 = 10

const headers_size: u64 = align_up(
    pe_section_table_foa +
        section_count * pe_section_header_size,
    pe_default_file_align
)
const text_raw: u64 = headers_size
const data_raw: u64 = text_raw + pe_default_file_align
const rsrc_raw: u64 = data_raw + pe_default_file_align
const reloc_raw: u64 = rsrc_raw + pe_default_file_align

pe_begin_dll64();
pe_headers_dll64(section_count);

pe_begin_section_at(
    ".text",
    text_row,
    text_rva,
    text_raw
);
text_start:
dll_main:
    mov eax, 1
    ret
text_end:
pe_align_section_file(text_row);

pe_begin_section_at(
    ".data",
    data_row,
    data_rva,
    data_raw
);
data_start:
pointer0:
    dq(0);
pointer1:
    dq(0);
pointer2:
    dq(0);
data_end:
pe_align_section_file(data_row);

let relocs: list = pe_reloc_new()
relocs = pe_reloc_add_dir64_at(
    relocs,
    data_rva,
    pointer0,
    data_start
)
relocs = pe_reloc_add_dir64_at(
    relocs,
    data_rva,
    pointer1,
    data_start
)
relocs = pe_reloc_add_dir64_at(
    relocs,
    data_rva,
    pointer2,
    data_start
)

pe_begin_section_at(
    ".rsrc",
    rsrc_row,
    rsrc_rva,
    rsrc_raw
);
rsrc_start:
pe_resource_emit_single_numeric(
    resource_type_rcdata,
    1,
    pe_resource_lang_en_us
);
emit.bytes(b"XIRASM PE64");
resource_payload_end:
pe_resource_finish_single_numeric(
    rsrc_rva,
    rsrc_start,
    resource_payload_end,
    0
);
rsrc_end:
pe_align_section_file(rsrc_row);

pe_begin_section_at(
    ".reloc",
    reloc_row,
    reloc_rva,
    reloc_raw
);
reloc_start:
pe_reloc_assert_sorted(relocs);
pe_reloc_emit_grouped_sorted(relocs);
reloc_end:
pe_align_section_file(reloc_row);

pe_finalize_section64_auto(
    text_row,
    pe_name_text,
    text_start,
    pe_text_chars
);
pe_finalize_section64_auto(
    data_row,
    pe_name_data,
    data_start,
    pe_data_chars
);
pe_finalize_section64_auto(
    rsrc_row,
    pe_name_rsrc,
    rsrc_start,
    pe_rsrc_chars
);
pe_finalize_section64_auto(
    reloc_row,
    pe_name_reloc,
    reloc_start,
    pe_reloc_chars
);

pe_finalize_entry(
    dll_main,
    text_start,
    text_rva
);
pe_finalize_image_size(
    reloc_rva,
    reloc_start,
    reloc_end
);
pe_finalize_code_size(
    text_start,
    text_end
);
pe_finalize_base_of_code(text_rva);
pe_finalize_resource_dir64(
    rsrc_rva,
    rsrc_start,
    pe_resource_root,
    pe_resource_end
);
pe_finalize_reloc_dir64(
    reloc_rva,
    reloc_start,
    pe_reloc_grouped_start,
    pe_reloc_grouped_end
);

defer {
    store.u64(pointer0, dll_main);
    store.u64(pointer1, pointer0);
    store.u64(pointer2, pointer1);

    store.u16(
        region_base() + pe_opt_dll_chars_foa,
        pe_dll_high_entropy_va |
            pe_dll_dynamic_base |
            pe_dll_nx_compat
    );

    store.u32(
        region_base() + pe_opt_size_of_init_data_foa,
        region_file_size(data_start) +
            region_file_size(rsrc_start) +
            region_file_size(reloc_start)
    );
}

pe_checksum_begin();
pe_checksum_add_region(text_start);
pe_checksum_add_region(data_start);
pe_checksum_add_region(rsrc_start);
pe_checksum_add_region(reloc_start);
pe_checksum_finish(reloc_start);
```

The resulting file is 3072 bytes:

```text
0x0000 .. 0x03ff  headers and four section rows
0x0400 .. 0x05ff  .text
0x0600 .. 0x07ff  .data
0x0800 .. 0x09ff  .rsrc
0x0a00 .. 0x0bff  .reloc
```

The three stored pointer values initially form this chain:

```text
pointer0 -> dll_main
pointer1 -> pointer0
pointer2 -> pointer1
```

When the image is loaded away from its preferred base, each value receives the
same image-base delta. The resource loader can find numeric type `10`, numeric
id `1`, language `0x0409`, and the payload `XIRASM PE64`.

### PE32 Changes

The PE32 form preserves the same section and directory plan. Change only the
width-specific parts:

| PE32+ form | PE32 form |
|---|---|
| `pe_begin_dll64` | `pe_begin_dll32` |
| `pe_headers_dll64` | `pe_headers_dll32` |
| `pe_section_table_foa` | `pe_section32_table_foa` |
| `pe_begin_section_at` | `pe_begin_section32_at` |
| `pe_finalize_section64_auto` | `pe_finalize_section32_auto` |
| `pe_finalize_resource_dir64` | `pe_finalize_resource_dir32` |
| `pe_finalize_reloc_dir64` | `pe_finalize_reloc_dir32` |
| `dq(0)` and `store.u64` | `dd(0)` and `store.u32` |
| `pe_reloc_add_dir64_at` | `pe_reloc_add_highlow_at` |
| `DIR64` | `HIGHLOW` |

Select 32-bit instruction encoding before emitting code:

```text
x86.use32()
```

For a standard 32-bit DLL entry that uses the platform calling convention,
return while removing its three stack arguments:

```text
ret 12
```

PE32 does not use `HIGH_ENTROPY_VA`. Its direct relocation-enabled flag set is:

```text
pe_dll_dynamic_base | pe_dll_nx_compat
```

The PE32 version of this layout also occupies 3072 bytes. Its three pointer
slots use 32-bit values and `HIGHLOW` relocation records, while the resource
tree and checksum workflow remain unchanged.

### Resource and Relocation Section Characteristics

Use characteristics that match the loader's intended access:

| Section | Direct characteristics | Meaning |
|---|---|---|
| `.data` | `pe_data_chars` | Initialized, readable, writable |
| `.rsrc` | `pe_rsrc_chars` | Initialized, readable |
| `.reloc` | `pe_reloc_chars` | Initialized, readable, discardable |

Neither `.rsrc` nor `.reloc` should be writable or executable in this design.
The loader may discard `.reloc` after applying the base relocations.

### Direct PE Relocation, Resource, and Checksum Checklist

Before accepting a direct PE image with these features, confirm:

1. `SizeOfHeaders` covers the complete section table.
2. The first raw pointer begins at or after `SizeOfHeaders`.
3. Raw section ranges do not overlap.
4. Every stored absolute image address has the correct relocation width.
5. PE32 uses `HIGHLOW`.
6. PE32+ uses `DIR64`.
7. Relocation records are sorted by RVA.
8. Relocation blocks are grouped by 4 KiB page.
9. Each block size includes required `ABSOLUTE` padding.
10. The relocation directory covers only emitted relocation blocks.
11. `DYNAMIC_BASE` is present only when the relocation contract is complete.
12. PE32+ high-entropy policy is paired with a relocatable image.
13. Resource directory links are relative to the resource root.
14. Resource data entries contain payload RVAs, not FOAs.
15. The resource directory covers the complete resource tree and payload area.
16. `.rsrc` is readable and non-executable.
17. `.reloc` is readable, non-executable, and normally discardable.
18. SizeOfInitializedData includes all file-backed metadata sections.
19. Pointer, directory, flag, and size finalizers run before checksum folding.
20. Checksum regions are registered in final physical file order.
21. The final checksum includes the file size.
22. Every data-directory slot has one finalizer owner.

The next part applies the same direct-control discipline to COFF object files,
where section numbers, symbol indexes, relocation rows, and linker-visible BSS
replace PE data directories as the main consistency contracts.

## Part III: Direct COFF Construction

## 7. COFF Sections and Symbols

A COFF object is not a loadable image. It is a collection of section
contributions, symbol definitions, unresolved references, and relocation
records that a linker combines into a final image.

The direct COFF layer therefore exposes different responsibilities from PE:

- there is no optional header or image base;
- section values are section-relative;
- public definitions and unresolved names live in one symbol table;
- the symbol table is followed by one shared string table;
- section rows refer to raw data and relocation records;
- BSS reserves linker-visible storage without storing payload bytes.

This chapter builds sections and symbols only. The XIRASM object contains no
relocation records. A native consumer object references its public symbols,
which proves that section numbers, symbol values, symbol names, and BSS size
are usable by a linker. Chapter 8 adds relocations and weak externals.

### Import the Direct COFF Family

Use the common direct helper:

```text
import("format/coff.inc")
```

Do not import `coff32.inc`, `coff64.inc`, or the ordinary format facade into
the same construction.

The common direct layer contains both machine variants:

| Object | Header helper | Machine |
|---|---|---:|
| COFF32 | `coff_begin32` | `coff_machine_i386` |
| COFF64 | `coff_begin64` | `coff_machine_amd64` |

Select 32-bit instruction encoding separately when constructing a COFF32
object:

```text
x86.use32()
```

The COFF container width and instruction mode are related choices, but they
remain separate facts.

### Plan the Entire Object Before Emission

The COFF file header is emitted before section payloads. It already contains:

- the machine;
- the section count;
- the symbol-table FOA;
- the symbol-record count;
- file characteristics.

The direct header call therefore requires the final symbol-table position:

```text
coff_begin64(section_count, symbol_table_foa, symbol_count)
```

or:

```text
coff_begin32(section_count, symbol_table_foa, symbol_count)
```

The caller must plan the raw section ranges first:

```text
first raw FOA
  = aligned end of file header and section rows

next raw FOA
  = aligned end of the previous file-backed section

symbol-table FOA
  = aligned end of the final file-backed section
```

The direct helpers provide:

| Helper | Result |
|---|---|
| `coff_first_raw_foa` | First raw byte after all section rows |
| `coff_next_foa` | Aligned FOA after one raw range |
| `coff_symbol_foa` | FOA of one symbol record |
| `coff_string_table_foa` | FOA immediately after all symbol records |

These are physical file calculations. They are not section-relative symbol
values.

### Section Rows and Section Numbers Are Different

COFF uses two section namespaces:

| Namespace | Base | Used by |
|---|---:|---|
| Section header row | 0 | `coff_finalize_section` |
| Symbol section number | 1 | `coff_public`, `coff_static` |

For three rows:

| Section | Header row | Symbol section number |
|---|---:|---:|
| `.text` | 0 | 1 |
| `.data` | 1 | 2 |
| `.bss` | 2 | 3 |

Section number zero has a different meaning:

```text
coff_sym_undefined
```

An external symbol with section number zero is not defined by the current
object. The linker must resolve it from another object or library.

Do not pass a zero-based row directly as a defined symbol's section number.

### Section Values Begin at Zero

Each COFF object section has its own address space. A symbol's `Value` field is
an offset from the beginning of its section:

```text
symbol value = label address - section start
```

It is not:

- a PE RVA;
- a final virtual address;
- a file offset;
- an offset from the beginning of the object.

The section start itself normally has value zero. A later label in the same
section has the byte offset produced by that section's contents.

### File-Backed Sections

Begin a direct section at an explicit raw pointer:

```text
coff_begin_section(name, raw_pointer)
```

Emit its bytes, then close the physical range:

```text
coff_end_section(raw_size)
```

The explicit form is useful when the object plan already contains fixed raw
sizes. `coff_end_section` pads the section to the declared physical extent.

Finalize the matching section row with:

```text
coff_finalize_section(
    row,
    name,
    raw_size,
    raw_pointer,
    characteristics
)
```

The standard direct characteristics are:

| Section | Characteristics |
|---|---|
| `.text` | `coff_text_chars` |
| `.rdata` | `coff_rdata_chars` |
| `.data` | `coff_data_chars` |
| `.bss` | `coff_bss_chars` |

The characteristics include content class, permissions, and a section
alignment request for the linker.

### BSS Has Size but No Raw Pointer

COFF BSS is not represented as a file-backed zero array. Its section row must
describe the amount of storage the linker should allocate:

```text
SizeOfRawData   = logical BSS size
PointerToRawData = 0
```

The terminology is historical: for an uninitialized COFF section,
`SizeOfRawData` carries the section contribution size even though no raw bytes
are present.

Use a reserve-only region to establish the logical extent:

```text
begin BSS with physical pointer zero
reserve the required size
close the region
```

Then finalize it explicitly:

```text
coff_finalize_section(
    bss_row,
    coff_name_bss,
    bss_end - bss_start,
    0,
    coff_bss_chars
)
```

Do not use `coff_finalize_section_auto` for this case. That helper derives the
physical file size of a known region, while BSS requires a logical size and a
zero raw pointer.

### Symbol Records Are Fixed at 18 Bytes

Every ordinary COFF symbol record contains:

- an eight-byte name field;
- a section-relative value;
- a section number;
- a type;
- a storage class;
- an auxiliary-record count.

The direct helpers cover the common classes:

| Helper | Meaning |
|---|---|
| `coff_public` | Defined external symbol |
| `coff_static` | Defined object-local symbol |
| `coff_extrn` | Undefined external symbol |
| `coff_symbol` | Explicit class and type |

Function definitions normally use:

```text
coff_sym_type_function
```

Data definitions normally use:

```text
coff_sym_type_null
```

`symbol_count` is the number of 18-byte records, not merely the number of
source-level names. An auxiliary record consumes another symbol-table index
and must be included in the count. Chapter 8 uses that rule for weak external
symbols.

### Short Symbol Names

A name of at most eight bytes can be stored directly in the symbol record.
The `name0` argument is the little-endian eight-byte field.

The direct library provides constants for common names such as:

```text
coff_name_text
coff_name_data
coff_name_rdata
coff_name_bss
coff_name_main
coff_name__main
```

The leading underscore in `coff_name__main` is the conventional 32-bit C name
decoration. COFF64 C names are normally undecorated.

When every symbol name fits in eight bytes, finish the records with:

```text
coff_end_symbols(symbol_count)
```

This writes the required four-byte minimum string table.

### Long Symbol Names and the String Table

A longer symbol name is stored in the shared string table. Its eight-byte name
field becomes:

```text
first  four bytes = 0
second four bytes = string-table offset
```

Because `coff_symbol` accepts the complete field as a little-endian `u64`, the
encoded value is:

```text
name_field = string_offset << 32
```

String-table offsets are measured from the beginning of the string table,
including its four-byte size field. The first string therefore begins at
offset `4`.

The string table layout is:

```text
u32 total_size
first_name  0
second_name 0
...
```

`total_size` includes its own four bytes and every terminating zero.

If long names are present, emit the string table explicitly instead of calling
`coff_end_symbols`. The symbol records and strings must agree on every offset.

### Complete COFF64 Object

This object defines:

- `xirasm_value`, a function returning `42`;
- `xirasm_data`, an initialized integer containing `7`;
- `xirasm_scratch`, a 64-byte BSS array.

All three names require the COFF string table. The object itself contains no
relocation records.

```asm
import("format/coff.inc");

const section_count: u16 = 3
const symbol_count: u64 = 3

const text_raw: u64 = coff_first_raw_foa(
    section_count
)
const text_raw_size: u64 = 8
const data_raw: u64 = coff_next_foa(
    text_raw,
    text_raw_size,
    4
)
const data_raw_size: u64 = 4
const bss_size: u64 = 64
const symbol_table_foa: u64 = coff_next_foa(
    data_raw,
    data_raw_size,
    4
)

const name_value_offset: u64 = 4
const name_data_offset: u64 = name_value_offset + 13
const name_scratch_offset: u64 = name_data_offset + 12
const string_table_size: u64 = name_scratch_offset + 15

const name_xirasm_value: u64 = name_value_offset << 32
const name_xirasm_data: u64 = name_data_offset << 32
const name_xirasm_scratch: u64 = name_scratch_offset << 32

coff_begin64(
    section_count,
    symbol_table_foa,
    symbol_count
);

coff_begin_section(
    ".text",
    text_raw
);
text_start:
xirasm_value:
    mov eax, 42
    ret
text_end:
coff_end_section(text_raw_size);

coff_begin_section(
    ".data",
    data_raw
);
data_start:
xirasm_data:
    dd(7);
data_end:
coff_end_section(data_raw_size);

coff_begin_section(".bss", 0);
bss_start:
xirasm_scratch:
    reserve(bss_size);
bss_end:
coff_align_section_file();

region.begin(
    ".symtab",
    symbol_table_foa,
    symbol_table_foa
);
coff_public(
    name_xirasm_value,
    xirasm_value - text_start,
    1,
    coff_sym_type_function
);
coff_public(
    name_xirasm_data,
    xirasm_data - data_start,
    2,
    coff_sym_type_null
);
coff_public(
    name_xirasm_scratch,
    xirasm_scratch - bss_start,
    3,
    coff_sym_type_null
);

string_table_start:
emit.u32(string_table_size);
emit.bytes(b"xirasm_value");
emit.u8(0);
emit.bytes(b"xirasm_data");
emit.u8(0);
emit.bytes(b"xirasm_scratch");
emit.u8(0);
string_table_end:
assert(
    string_table_end - string_table_start ==
        string_table_size
);

coff_finalize_section(
    0,
    coff_name_text,
    text_raw_size,
    text_raw,
    coff_text_chars
);
coff_finalize_section(
    1,
    coff_name_data,
    data_raw_size,
    data_raw,
    coff_data_chars
);
coff_finalize_section(
    2,
    coff_name_bss,
    bss_end - bss_start,
    0,
    coff_bss_chars
);
```

The physical object layout is:

| Range | Content |
|---|---|
| `0x0000 .. 0x008b` | File header and three section rows |
| `0x008c .. 0x0093` | `.text` |
| `0x0094 .. 0x0097` | `.data` |
| no raw range | `.bss` |
| `0x0098 .. 0x00cd` | Three symbol records |
| `0x00ce .. 0x00f9` | String table |

The object is 250 bytes. Its `.bss` row contains size `64` and raw pointer
zero. Its three symbol values are zero because each definition begins at the
start of its section.

### Consuming the Definitions from C

A native consumer can reference all three public definitions:

```c
extern int xirasm_value(void);
extern int xirasm_data;
extern unsigned char xirasm_scratch[64];

int main(void) {
    xirasm_scratch[63] = 35;
    return xirasm_value() +
        xirasm_data +
        xirasm_scratch[63] -
        84;
}
```

The return value is zero only if:

- the function symbol resolves to executable code;
- the initialized data symbol resolves to the value `7`;
- the linker allocates the complete 64-byte BSS contribution;
- the final byte of that BSS contribution is writable.

The XIRASM object needs no relocation records for this workflow. The consumer
object contains the references, and the linker resolves them against the three
public definitions.

### COFF32 Changes

The COFF32 object keeps the same section and symbol plan. Change:

| COFF64 | COFF32 |
|---|---|
| `coff_begin64` | `coff_begin32` |
| x86-64 instruction mode | `x86.use32()` |
| `xirasm_value` | `_xirasm_value` |
| `xirasm_data` | `_xirasm_data` |
| `xirasm_scratch` | `_xirasm_scratch` |

The leading underscore is part of each 32-bit COFF symbol name. It also changes
the string lengths and therefore every later string-table offset.

For the three decorated names:

```text
_xirasm_value   starts at offset 4
_xirasm_data    starts at offset 18
_xirasm_scratch starts at offset 31
total string-table size = 47
```

The resulting COFF32 object is 253 bytes. Its section rows and symbol section
numbers remain identical to the COFF64 plan.

### Direct Symbol Table Placement

The complete example places the symbol table with:

```text
region.begin(".symtab", symbol_table_foa, symbol_table_foa)
```

Both coordinates use the physical symbol-table position because symbol records
are metadata rather than section-relative program content.

`coff_begin_symbols` is useful when the current real file cursor already equals
the planned symbol-table FOA. After a reserve-only BSS region, make that
relationship explicit rather than assuming the current region's zero physical
cursor still represents the end of previous file-backed data.

The direct rule is simple:

```text
the header's PointerToSymbolTable
the symbol-table region's FOA
and the actual first symbol byte
must all identify the same file position
```

### Section and Symbol Checklist

Before accepting a direct COFF object without relocations, confirm:

1. The machine matches the instruction mode.
2. The header section count matches the emitted section rows.
3. The header symbol count matches all symbol and auxiliary records.
4. `PointerToSymbolTable` identifies the first symbol byte.
5. File-backed raw ranges do not overlap.
6. Every file-backed raw pointer and raw size describes existing bytes.
7. BSS carries its logical contribution size.
8. BSS has raw pointer zero.
9. Section rows use zero-based row numbers.
10. Defined symbols use one-based section numbers.
11. Undefined externals use section number zero.
12. Symbol values are offsets from their section start.
13. Function symbols use `coff_sym_type_function`.
14. Data symbols use the intended storage class and type.
15. Symbol indexes count every 18-byte record.
16. Auxiliary records are included in the header symbol count.
17. Short names occupy no more than eight bytes.
18. Long-name fields contain zero plus the correct string-table offset.
19. String-table offsets include the four-byte table-size field.
20. The string-table size includes every terminating zero.
21. Sections without relocations keep relocation pointer and count zero.
22. A native linker can resolve and consume every intended public definition.

Chapter 8 adds relocation records, undefined externals, symbol-index
relationships, PC-relative calls, absolute references, and weak external
aliases.

## 8. COFF Relocations and Linker Interoperability

A COFF object does not need to know the final address of every referenced
symbol. Instead, it preserves:

1. the bytes that contain an unresolved field;
2. a relocation record that identifies that field;
3. a symbol-table index that names the target.

The linker combines those three facts after it has placed every input section.

This chapter continues to use only:

```text
import("format/coff.inc")
```

The direct layer does not allocate symbol indexes, count relocation records, or
choose relocation types. Those remain explicit parts of the object plan.

### A Relocation Connects Three Records

Every direct COFF relocation connects:

| Object fact | Meaning |
|---|---|
| section contents | the field that the linker will rewrite |
| relocation row | the field offset, symbol index, and relocation type |
| symbol row | the definition or undefined external referenced by the row |

The relocation row itself is ten bytes:

```text
u32 VirtualAddress
u32 SymbolTableIndex
u16 Type
```

`VirtualAddress` is historical COFF terminology. In an object relocation, it
is the byte offset of the relocated field from the start of its section. It is
not:

- a file offset;
- an absolute address;
- an executable image RVA;
- the address of the instruction opcode.

`SymbolTableIndex` is a zero-based index into the complete symbol record
sequence. Auxiliary records occupy indexes too.

### Relocation Offsets Are Section-Relative

Use:

```text
coff_reloc_offset(section_start, field_label)
```

to derive the relocation offset from two logical addresses in the same
section.

For a direct call encoded as:

```text
E8 00 00 00 00
```

the relocation belongs to the four-byte displacement field, not to the `E8`
opcode.

If the call begins at section offset `5`, the field begins at offset `6`.
Therefore the relocation row records:

```text
VirtualAddress = 6
```

The helper:

```text
coff_reloc_at(section_start, field_label, symbol_index, relocation_type)
```

performs that subtraction and emits the row.

The machine-specific helpers also choose the relocation type:

```text
coff_reloc_amd64_rel32_at(...)
coff_reloc_i386_rel32_at(...)
```

### External References Need Object Relocations

A normal XIRASM label belongs to the current source program. The assembler can
resolve that label while producing the current output.

An undefined COFF external is different. Its final address is owned by the
linker, so the object must contain:

1. an undefined external symbol row;
2. a placeholder field in section contents;
3. a relocation row that connects the field to that symbol row.

The direct layer does not turn an undefined COFF symbol into an assembler
label. For an external call, emit the instruction field explicitly:

```text
db(0xe8)
call_disp:
dd(0)
```

The zero is the initial addend for a call with no additional displacement.
The linker replaces that field according to the relocation type.

This manual field emission is specific to direct object construction. The
ordinary format facade accepts a named relocation declaration and performs
the index planning on behalf of the user.

### Choose the Relocation Type by Machine

`coff.inc` exposes these direct relocation kinds:

| Machine | Constant | Field meaning |
|---|---|---|
| AMD64 | `coff_rel_amd64_addr64` | 64-bit absolute address |
| AMD64 | `coff_rel_amd64_addr32` | 32-bit absolute address |
| AMD64 | `coff_rel_amd64_addr32nb` | 32-bit address without image base |
| AMD64 | `coff_rel_amd64_rel32` | 32-bit PC-relative displacement |
| i386 | `coff_rel_i386_dir32` | 32-bit absolute address |
| i386 | `coff_rel_i386_dir32nb` | 32-bit address without image base |
| i386 | `coff_rel_i386_rel32` | 32-bit PC-relative displacement |

The corresponding `_at` helpers are:

```text
coff_reloc_amd64_addr64_at
coff_reloc_amd64_addr32_at
coff_reloc_amd64_addr32nb_at
coff_reloc_amd64_rel32_at
coff_reloc_i386_dir32_at
coff_reloc_i386_dir32nb_at
coff_reloc_i386_rel32_at
```

Use a relative relocation for an x86 or x86-64 direct `call` or `jmp`
displacement.

Use an absolute relocation only when the section contents truly store an
address. The field width in the section must agree with the relocation kind.
For example, an AMD64 `ADDR64` relocation belongs to an eight-byte field.

### Plan Relocation and Symbol Tables Together

The file header needs the symbol-table FOA before section contents begin.
The section row needs the relocation-table FOA and relocation count.

Plan the complete order first:

```text
file header
section rows
section raw data
section relocation tables
symbol table
string table
```

For one `.text` section:

```text
text_raw =
    coff_first_raw_foa(section_count)

reloc_table_foa =
    coff_next_foa(text_raw, text_raw_size, 4)

symbol_table_foa =
    coff_next_foa(
        reloc_table_foa,
        relocation_count * coff_reloc_size,
        4
    )
```

If several sections contain relocations, each section needs its own contiguous
relocation table. Each section row then stores the FOA and row count of its own
table.

The tables may be physically adjacent, but their ownership remains
section-specific.

### Emit and Count Relocation Rows

A direct relocation table can be emitted in a metadata region:

```text
region.begin(".reloc.text", 0, reloc_table_foa)

reloc_start:
coff_reloc_amd64_rel32_at(
    text_start,
    call_disp,
    helper_symbol_index
)
reloc_end:
```

The logical base of this metadata region is not used as a runtime address. Its
physical base is the relocation-table FOA.

Derive the count from the bytes actually emitted:

```text
coff_reloc_count(reloc_start, reloc_end)
```

The helper verifies that the range is non-negative and divisible by the
ten-byte relocation-record size.

Useful table-position helpers are:

```text
coff_reloc_foa(reloc_table_foa, row)
coff_reloc_table_end_foa(reloc_table_foa, count)
```

### Finalize the Owning Section Row

A section with relocations needs all of these row fields:

```text
Name
SizeOfRawData
PointerToRawData
PointerToRelocations
NumberOfRelocations
Characteristics
```

Use:

```text
coff_finalize_section_reloc(
    row,
    name,
    raw_size,
    raw_ptr,
    reloc_ptr,
    reloc_count,
    characteristics
)
```

when the direct object plan already knows the physical values.

Use:

```text
coff_finalize_section_reloc_auto(
    row,
    name,
    section_start,
    reloc_ptr,
    reloc_count,
    characteristics
)
```

when the section is file-backed and its final raw size and raw pointer should
come from stable region facts.

Do not use the automatic helper for a reserve-only BSS section. BSS requires an
explicit logical size and raw pointer zero, as described in Chapter 7.

### Complete COFF64 External Call

The following object defines `value()` and calls an undefined external
`helper(int)`.

The symbol indexes are:

| Index | Record |
|---:|---|
| `0` | static `.text` section symbol |
| `1` | public `value` function |
| `2` | undefined external `helper` function |

The relocation therefore targets symbol index `2`.

```asm
import("format/coff.inc");

const section_count: u16 = 1
const symbol_count: u64 = 3
const reloc_count: u64 = 1

const text_raw: u64 = coff_first_raw_foa(section_count)
const text_raw_size: u64 = 19
const reloc_table_foa: u64 = coff_next_foa(text_raw, text_raw_size, 4)
const symbol_table_foa: u64 = coff_next_foa(
    reloc_table_foa,
    reloc_count * coff_reloc_size,
    4
)

const name_value: u64 = 0x00000065756c6176
const name_helper: u64 = 0x00007265706c6568

coff_begin64(section_count, symbol_table_foa, symbol_count);

coff_begin_section(".text", text_raw);
text_start:
value:
    sub rsp, 40
    mov ecx, 42
    db(0xe8);
call_disp:
    dd(0);
    add rsp, 40
    ret
coff_end_section(text_raw_size);

region.begin(".reloc.text", 0, reloc_table_foa);
reloc_start:
coff_reloc_amd64_rel32_at(text_start, call_disp, 2);
reloc_end:

region.begin(".symtab", 0, symbol_table_foa);
coff_static(coff_name_text, 0, 1, coff_sym_type_null);
coff_public(name_value, value - text_start, 1, coff_sym_type_function);
coff_extrn(name_helper, coff_sym_type_function);
coff_end_symbols(symbol_count);

coff_finalize_section_reloc(
    0,
    coff_name_text,
    text_raw_size,
    text_raw,
    reloc_table_foa,
    coff_reloc_count(reloc_start, reloc_end),
    coff_text_chars
);

defer {
    assert(coff_reloc_offset(text_start, call_disp) == 10);
    assert(coff_reloc_count(reloc_start, reloc_end) == reloc_count);
}
```

The resulting object is 150 bytes:

| Range | Content |
|---|---|
| `0x0000 .. 0x003b` | file header and one section row |
| `0x003c .. 0x004e` | nineteen `.text` bytes |
| `0x004f` | physical alignment byte |
| `0x0050 .. 0x0059` | one relocation record |
| `0x005a .. 0x005b` | physical alignment bytes |
| `0x005c .. 0x0091` | three symbol records |
| `0x0092 .. 0x0095` | minimum string table |

The relocation row contains:

```text
VirtualAddress   = 10
SymbolTableIndex = 2
Type             = 0x0004
```

`0x0004` is the AMD64 `REL32` relocation.

### Link the Object with C

A native consumer can define the external helper and call the public function:

```c
extern int value(void);

int helper(int input) {
    return input + 7;
}

int main(void) {
    return value() - 49;
}
```

The linked program returns zero only if:

- the C compiler publishes `helper` under the expected COFF symbol name;
- the object relocation selects the `helper` symbol row;
- the linker writes the correct PC-relative call displacement;
- the caller reserves the required shadow space and keeps the stack aligned;
- the x86-64 calling convention passes `42` in `ecx`;
- the public `value` symbol is callable from the C object.

The object contains no final executable address for `helper`. The linker
supplies it.

This minimal function is sufficient for normal execution. A production AMD64
function that changes `rsp` and must participate in system unwinding also needs
appropriate unwind metadata. That metadata is separate from the relocation
contract described here.

### COFF32 Changes

The 32-bit object uses the same record plan but changes the ABI-facing details:

| COFF64 | COFF32 |
|---|---|
| `coff_begin64` | `coff_begin32` |
| x86-64 instruction mode | `x86.use32()` |
| `value` | `_value` |
| `helper` | `_helper` |
| argument in `ecx` | argument on the stack |
| `coff_reloc_amd64_rel32_at` | `coff_reloc_i386_rel32_at` |
| relocation type `0x0004` | relocation type `0x0014` |

The 32-bit function body can use:

```text
value:
    db(0x6a, 42)
    db(0xe8)
call_disp:
    dd(0)
    add esp, 4
    ret
```

The field begins at section offset `3`, so the relocation row contains:

```text
VirtualAddress   = 3
SymbolTableIndex = 2
Type             = 0x0014
```

The caller removes the four-byte argument because this example uses the
32-bit C calling convention in which arguments are passed on the stack.

The complete COFF32 object is 142 bytes and links against the same C source
compiled for the 32-bit target.

### Absolute Address Relocations

PC-relative calls are only one relocation use.

An object may also contain a stored address:

```text
dq(0)
```

For an AMD64 target, attach:

```text
coff_reloc_amd64_addr64_at(
    section_start,
    address_field,
    target_symbol_index
)
```

The relocation belongs to the eight-byte field label.

For a four-byte absolute field, choose the matching 32-bit relocation only
when the final value is valid for that field and the target environment's
linker contract.

`ADDR32NB` and `DIR32NB` describe addresses without the executable image base.
They are useful when constructing data that the linker interprets relative to
the image rather than as a full process address.

The direct layer does not validate whether a chosen relocation type is
appropriate for the instruction or data field. The field width, machine,
relocation type, and final linker use must agree.

### Weak External Aliases

A weak external alias lets an undefined symbol fall back to another symbol.

The direct helper:

```text
coff_weak_external_alias(
    weak_name,
    fallback_symbol_index,
    symbol_type
)
```

emits two consecutive 18-byte records:

1. the undefined weak external symbol;
2. its auxiliary alias record.

The auxiliary record stores the fallback symbol index and
`coff_weak_search_alias`.

For this record order:

| Index | Record |
|---:|---|
| `0` | section symbol |
| `1` | public entry function |
| `2` | public fallback function |
| `3` | weak external base record |
| `4` | weak external auxiliary record |

use:

```text
coff_weak_external_alias(weak_name, 2, coff_sym_type_function)
```

and make the relocation target symbol index `3`.

The file header's symbol count is `5`, not `4`, because the auxiliary record is
part of the symbol-table index space.

If another object supplies a strong definition for the weak name, the linker
may select it. Otherwise the alias resolves to the fallback symbol at index
`2`.

### Symbol Names Are Part of the ABI

Linker interoperability depends on exact symbol spelling.

For the C ABI used in these examples:

| Target | Typical C external name |
|---|---|
| AMD64 COFF | undecorated, such as `helper` |
| i386 COFF | leading underscore, such as `_helper` |

Other calling conventions can use different decoration.

The direct COFF layer does not decorate names. It writes exactly the bytes
supplied in the symbol record or string table.

This means all of these must agree:

- the source-language declaration;
- the symbol-table bytes;
- the target machine;
- the calling convention;
- the linked consumer or provider.

### Linker Interoperability Rules

A structurally valid object may still fail to link or run if its ABI facts do
not agree.

Check:

1. The COFF machine matches the encoded instructions.
2. Every relocation type is defined for that machine.
3. The relocated field has the required width.
4. The relocation offset identifies the field, not the opcode.
5. The relocation symbol index identifies the intended base symbol record.
6. Symbol indexes include auxiliary records.
7. Undefined externals use section number zero.
8. Public definitions use the correct one-based section number.
9. Function symbol types are marked as functions.
10. Symbol spelling matches the linked language ABI.
11. Function arguments and return values follow the same calling convention.
12. Section characteristics permit the linked use.

Real linking is the final proof that the format records and ABI assumptions
agree.

### Direct COFF Relocation Checklist

Before accepting a direct COFF object with relocations, confirm:

1. The complete symbol order is planned before header emission.
2. The header symbol count includes auxiliary rows.
3. Every relocation target uses a zero-based symbol-table index.
4. Every defined symbol uses a one-based section number.
5. Every undefined external uses section number zero.
6. Relocation offsets are relative to the owning section.
7. Relocation offsets identify the patch field.
8. The patch field contains the intended initial addend.
9. The relocation type matches the machine.
10. The relocation type matches the field width.
11. Each relocation table is contiguous.
12. Each section row points to its own relocation table.
13. Each section row records the exact relocation count.
14. Relocation tables do not overlap raw section data.
15. The symbol table begins after every relocation table.
16. `PointerToSymbolTable` identifies the first symbol record.
17. Short and long symbol names follow the Chapter 7 rules.
18. Weak external auxiliary rows occupy symbol indexes.
19. C-visible symbol names match the target ABI.
20. A real linker can consume the object.
21. The linked program exercises the relocated reference.

Chapter 9 begins direct ELF construction with executable program headers,
LOAD segments, file offsets, virtual addresses, file sizes, and memory sizes.

## Part IV: Direct ELF Construction

## 9. ELF Executable Program Headers

An ELF executable is loaded from its program header table.

For each loadable range, the table tells the operating system:

- which file bytes belong to the segment;
- where those bytes appear in virtual memory;
- how much memory the segment occupies;
- which read, write, and execute permissions apply;
- which alignment relationship the loader must preserve.

This chapter uses only:

```text
import("format/elfexe.inc")
```

It constructs fixed-address ELF32 and ELF64 executables directly. PIE,
dynamic imports, object files, and shared objects use additional contracts and
are covered elsewhere.

### The Loader Uses Program Headers

The executable header contains:

```text
ELF class
file type
machine
entry address
program-header table offset
program-header row size
program-header count
```

Each `PT_LOAD` row contains:

```text
p_offset  file offset of the segment
p_vaddr   virtual address of the segment
p_paddr   physical address field, normally equal to p_vaddr here
p_filesz  bytes taken from the file
p_memsz   bytes present in memory
p_flags   read, write, and execute permissions
p_align   loader alignment
```

The loader does not need an ELF section-header table to start a static
syscall-only executable. The examples in this chapter set:

```text
e_shoff    = 0
e_shnum    = 0
e_shstrndx = 0
```

Section headers serve different consumers, such as linkers and debugging
tools. Program headers describe the runtime image.

### Header and Row Sizes

The direct helpers expose the fixed record sizes:

| Record | ELF64 | ELF32 |
|---|---:|---:|
| executable header | `64` | `52` |
| program header | `56` | `32` |

For two program headers:

```text
ELF64: 64 + 2 * 56 = 176
ELF32: 52 + 2 * 32 = 116
```

`elf64_first_segment_foa(2)` aligns the ELF64 result to `176`.

`elf32_first_segment_foa(2)` aligns the ELF32 result to `128`.

The alignment used by these helpers is file-structure alignment for the first
payload byte. It is not a request to insert a 4 KiB file hole.

### File and Memory Coordinates Are Independent

Every `PT_LOAD` has two coordinate systems:

| Coordinate | Meaning |
|---|---|
| `p_offset` | physical position in the file |
| `p_vaddr` | logical position in the process image |

The next file-backed segment can begin immediately after the previous
segment's actual file bytes.

Its virtual address can advance to another page.

This allows:

```text
compact physical file
separate virtual pages
different page permissions
```

Do not make the second segment's FOA equal to its virtual page distance.
That would turn a virtual-memory separation requirement into thousands of
physical zero bytes.

### Page Congruence

For a loadable segment:

```text
p_vaddr % p_align == p_offset % p_align
```

The file offset does not need to be zero modulo `p_align`.

For example:

```text
p_offset = 0x00bd
p_vaddr  = 0x4010bd
p_align  = 0x1000
```

Both values have page offset `0x0bd`.

This lets the segment reuse compact file bytes while appearing on a separate
virtual page.

The direct layer does not choose this virtual address automatically. The
caller must ensure:

1. congruence is preserved;
2. segment memory ranges do not overlap incorrectly;
3. permission boundaries remain meaningful.

### File Size and Memory Size Are Different

`p_filesz` describes bytes present in the file.

`p_memsz` describes bytes present after loading.

The required relationship is:

```text
p_memsz >= p_filesz
```

When:

```text
p_memsz > p_filesz
```

the loader supplies zero-initialized memory after the file-backed prefix.
This is the program-header form of BSS.

For:

```text
dd(0)
rb(64)
```

the segment contributes:

```text
p_filesz = 4
p_memsz  = 68
```

The trailing 64 reserved bytes do not occupy the file.

### Close Regions Without Adding File Holes

After emitting a file-backed segment, use:

```text
region.file_align(1)
```

to close the region at its exact physical end.

Alignment `1` means:

```text
commit the region's real file extent
add no padding bytes
```

It does not mean that ELF's loader alignment is `1`.

The program header still uses:

```text
p_align = elf_default_page_align
```

which is `0x1000`.

These are different operations:

| Operation | Purpose |
|---|---|
| `region.file_align(1)` | close the physical output region exactly |
| `p_align = 0x1000` | describe loader page congruence |

### Choose the Explicit Finalizer for Independent Coordinates

The most general direct helpers are:

```text
elfexe_finalize_phdr64(
    row,
    type,
    flags,
    offset,
    vaddr,
    filesz,
    memsz,
    alignment
)

elfexe_finalize_phdr32(
    row,
    type,
    flags,
    offset,
    vaddr,
    filesz,
    memsz,
    alignment
)
```

They accept independent file and memory facts.

Use them when:

- later LOAD segments use compact FOAs but separate virtual pages;
- `p_filesz` and `p_memsz` differ;
- the segment plan is intentionally explicit.

The convenience helpers have narrower contracts.

`elfexe_finalize_load64` and `elfexe_finalize_load32` derive both sizes from:

```text
end - start
```

They therefore describe a fully file-backed LOAD.

The `_auto` load helpers derive the virtual address from:

```text
image_base + region_file_offset(start)
```

Use that relationship only when it is the intended address model.

It is not sufficient for a compact later LOAD that must move to a separate
virtual page.

### Begin Segments with Explicit Coordinates

The convenience begin helpers:

```text
elfexe_begin_segment64(name, file_offset)
elfexe_begin_segment32(name, file_offset)
```

derive:

```text
virtual address = default image base + file offset
```

That is useful for a simple first LOAD.

For independent coordinates, use the generic region operation directly:

```text
region.begin(name, virtual_address, file_offset)
```

This is still the direct ELF model:

- `elfexe.inc` emits and finalizes the ELF records;
- the region API provides the logical and physical output coordinates.

### Entry Addresses Use Logical Position

The entry address is a virtual address.

Use:

```text
elfexe_finalize_entry64(entry_label, segment_start, segment_vaddr)
elfexe_finalize_entry32(entry_label, segment_start, segment_vaddr)
```

The stored entry is:

```text
segment_vaddr + (entry_label - segment_start)
```

Do not derive the entry from the final file offset unless the chosen segment
mapping deliberately makes those values correspond.

### Segment Permissions

Use separate virtual pages for writable data and executable code.

The common flags are:

| Purpose | Flags |
|---|---|
| executable code | `elf_pf_r \| elf_pf_x` |
| writable data and BSS | `elf_pf_r \| elf_pf_w` |
| read-only data | `elf_pf_r` |

Avoid a LOAD that combines write and execute permissions unless the runtime
design specifically requires it.

Compact FOAs do not require combined virtual permissions. Two segments can
use adjacent file bytes while mapping to separate virtual pages.

### Complete ELF64 Executable

The following ELF64 executable uses:

- one read-execute LOAD for code;
- one read-write LOAD for initialized data and BSS;
- compact, consecutive file bytes;
- separate virtual pages;
- a RIP-relative reference from code to data.

The initialized data contains exit status zero. The program loads that value
and performs the exit system call.

```asm
import("format/elfexe.inc");

const ph_count: u16 = 2
const text_foa: u64 = elf64_first_segment_foa(ph_count)
const text_vaddr: u64 = elf_default_base64 + text_foa

elfexe_begin64(ph_count);

region.begin(".text", text_vaddr, text_foa);
text_start:
start:
    mov edi, [rel data_start]
    mov eax, 60
    syscall
text_end:
region.file_align(1);

const data_foa: u64 = file_offset()
const data_vaddr: u64 = elf_default_base64 + elf_default_page_align + data_foa

region.begin(".data", data_vaddr, data_foa);
data_start:
    dd(0);
    rb(64);
data_end:
region.file_align(1);

elfexe_finalize_entry64(start, text_start, text_vaddr);
elfexe_finalize_phdr64(
    0,
    elf_pt_load,
    elf_pf_r | elf_pf_x,
    text_foa,
    text_vaddr,
    text_end - text_start,
    text_end - text_start,
    elf_default_page_align
);
elfexe_finalize_phdr64(
    1,
    elf_pt_load,
    elf_pf_r | elf_pf_w,
    data_foa,
    data_vaddr,
    4,
    data_end - data_start,
    elf_default_page_align
);

defer {
    assert(region_file_size(text_start) == text_end - text_start);
    assert(region_file_size(data_start) == 4);
    assert(region_logical_size(data_start) == data_end - data_start);
    assert(
        (text_vaddr % elf_default_page_align) ==
        (text_foa % elf_default_page_align)
    );
    assert(
        (data_vaddr % elf_default_page_align) ==
        (data_foa % elf_default_page_align)
    );
}
```

The executable is 193 bytes.

Its executable header contains:

```text
class      ELF64
type       ET_EXEC
machine    x86-64
entry      0x4000b0
phoff      64
phentsize  56
phnum      2
```

Its program headers are:

| Row | Flags | `p_offset` | `p_vaddr` | `p_filesz` | `p_memsz` |
|---:|---|---:|---:|---:|---:|
| `0` | `R X` | `176` | `0x4000b0` | `13` | `13` |
| `1` | `RW` | `189` | `0x4010bd` | `4` | `68` |

The physical file ends at:

```text
189 + 4 = 193
```

The 64 BSS bytes do not appear in the file.

### Why the Two LOADs Can Share a File Page

Both segment offsets are below `0x1000`:

```text
text p_offset = 0x0b0
data p_offset = 0x0bd
```

Their virtual page bases differ:

```text
text page = 0x400000
data page = 0x401000
```

The loader can map the same compact file page into different virtual pages
with different permissions.

This preserves:

```text
small file
RX code page
RW data page
no RWX LOAD
```

### Cross-Segment References Use Logical Addresses

The instruction:

```text
mov edi, [rel data_start]
```

is encoded from the final logical addresses of the two regions.

Its displacement is not based on the distance between their file offsets.

This distinction is essential:

```text
file distance    = 189 - 176
virtual distance = 0x4010bd - 0x4000b0
```

The frontend fixup resolves the logical distance. The ELF program header
describes how the relevant bytes enter memory.

### ELF32 Changes

The ELF32 example keeps the same two-LOAD plan.

Change:

| ELF64 | ELF32 |
|---|---|
| `elfexe_begin64` | `elfexe_begin32` |
| `elfexe_finalize_entry64` | `elfexe_finalize_entry32` |
| `elfexe_finalize_phdr64` | `elfexe_finalize_phdr32` |
| `elf64_first_segment_foa` | `elf32_first_segment_foa` |
| x86-64 mode | `x86.use32()` |
| exit status register `edi` | exit status register `ebx` |
| system call instruction | `int 0x80` |

The code body is:

```text
start:
    mov ebx, [data_start]
    mov eax, 1
    int 0x80
```

The executable is 145 bytes.

Its executable header contains:

```text
class      ELF32
type       ET_EXEC
machine    i386
entry      0x08048080
phoff      52
phentsize  32
phnum      2
```

Its program headers are:

| Row | Flags | `p_offset` | `p_vaddr` | `p_filesz` | `p_memsz` |
|---:|---|---:|---:|---:|---:|
| `0` | `R X` | `128` | `0x08048080` | `13` | `13` |
| `1` | `RW` | `141` | `0x0804908d` | `4` | `68` |

The physical file ends at:

```text
141 + 4 = 145
```

The 32-bit instruction uses an absolute address field rather than an x86-64
RIP-relative field. Because this is a fixed-address `ET_EXEC`, the assembler
can write the final logical data address directly.

### Fixed Executables and PIE Are Different Plans

`elfexe_begin64` emits:

```text
ET_EXEC
default image base 0x400000
```

`elfexe_begin32` emits:

```text
ET_EXEC
default image base 0x08048000
```

The direct helper:

```text
elfexe_begin64_at(program_header_count, file_type, image_base)
```

can emit another 64-bit file type and base, but the complete address and
relocation plan must agree with that choice.

Do not turn a fixed-address executable into PIE by changing only `e_type`.
Position-independent code, entry calculation, dynamic metadata, and
relocations must form one consistent design.

### Direct ELF Executable Checklist

Before accepting a direct ELF executable, confirm:

1. The ELF class matches the instruction mode.
2. The machine matches the instruction encoding.
3. The file type matches the address model.
4. The program-header count matches the emitted rows.
5. The program-header row size matches the ELF class.
6. The entry is a virtual address inside an executable LOAD.
7. Every LOAD has `p_memsz >= p_filesz`.
8. Every LOAD satisfies page congruence.
9. File ranges do not overlap incorrectly.
10. Virtual memory ranges do not overlap incorrectly.
11. Writable and executable content use appropriate permissions.
12. Compact file offsets are not expanded into virtual page-sized holes.
13. Tail BSS increases `p_memsz` without increasing `p_filesz`.
14. `region.file_align(1)` closes regions without adding padding.
15. Cross-segment fixups use logical addresses.
16. The final file size reaches the end of the last file-backed LOAD.
17. The program headers describe every byte required at runtime.
18. A real loader can start and run the executable.

Chapter 10 applies the same coordinate discipline to ELF object files, where
section headers, symbols, REL records, and RELA records replace the executable
program-header plan.

## 10. ELF Object Sections, Symbols, REL, and RELA

An ELF relocatable object is a linker input.

It does not describe a process image and does not contain program headers.
Instead, it provides:

- named sections;
- section types, sizes, flags, and alignments;
- local and global symbols;
- undefined symbols that another object must provide;
- relocation records that tell the linker which fields to rewrite.

This chapter uses only:

```text
import("format/elfobj.inc")
```

The direct object layer requires the caller to plan section indexes, symbol
indexes, string offsets, table offsets, and relocation records explicitly.
Use the ordinary format facade when those details should be generated
automatically.

### Relocatable Objects Use Section Headers

An ELF executable is loaded through program headers.

An ELF object is consumed through section headers.

Its ELF header uses:

```text
e_type  = ET_REL
e_entry = 0
e_phoff = 0
e_phnum = 0
```

The important object-header fields are:

```text
e_shoff     file offset of the section-header table
e_shentsize size of one section-header row
e_shnum     number of section-header rows
e_shstrndx  index of the section-name string table
```

The first section-header row must be the null row at index zero.

### Direct Object Record Sizes

The direct helpers expose the fixed record sizes:

| Record | ELF64 | ELF32 |
|---|---:|---:|
| ELF header | `64` | `52` |
| section header | `64` | `40` |
| symbol | `24` | `16` |
| relocation with addend | `24` | not used here |
| relocation without addend | not used here | `8` |

The examples use:

```text
ELF64 x86-64 -> SHT_RELA rows
ELF32 i386   -> SHT_REL rows
```

This is an ABI choice, not merely a difference in integer width.

### Plan the Section Indexes First

Every cross-reference uses a section index.

The complete example uses:

| Index | Section | Purpose |
|---:|---|---|
| `0` | null | required empty row |
| `1` | `.text` | executable code |
| `2` | `.data` | initialized writable data |
| `3` | `.bss` | zero-initialized writable data |
| `4` | `.rela.text` | relocations applied to `.text` |
| `5` | `.symtab` | static symbol table |
| `6` | `.strtab` | symbol-name strings |
| `7` | `.shstrtab` | section-name strings |
| `8` | `.note.GNU-stack` | non-executable stack declaration |

These indexes are later stored in:

- symbol `st_shndx` fields;
- relocation-section `sh_link` and `sh_info`;
- symbol-table `sh_link`;
- the ELF header's `e_shstrndx`.

Changing the section order requires updating every dependent index.

### File-Backed Sections

For a file-backed section, the direct helper sequence is:

```text
elfobj_begin_section(name, file_offset)
emit the section bytes
elfobj_end_section(raw_size)
```

`elfobj_begin_section` starts the section with a section-relative logical
address of zero and the supplied physical file offset.

`elfobj_end_section` extends the physical section to the declared raw size.
Use it only when that raw size is supposed to occupy the file.

Small alignment gaps between file-backed sections may contain padding. A
virtual-memory size must not be converted into a physical file gap.

### NOBITS and BSS

An ELF BSS section uses:

```text
type  = SHT_NOBITS
flags = SHF_ALLOC | SHF_WRITE
size  = logical allocation size
```

Its `sh_size` is meaningful, but it contributes no payload bytes.

At the direct layer, create the logical region explicitly:

```text
region.begin(".bss", 0, bss_foa)
bss_start:
    reserve(64)
bss_end:
region.file_align(1)
```

Then emit a section-header row with:

```text
sh_offset = bss_foa
sh_size   = bss_end - bss_start
```

Do not call:

```text
elfobj_end_section(64)
```

for BSS. That helper describes 64 physical bytes and would write padding into
the object.

Because `SHT_NOBITS` consumes no file bytes, the next file-backed section may
begin at the same FOA:

```text
.bss sh_offset       = 0x68
.rela.text sh_offset = 0x68
```

The section types tell the linker why those offsets do not conflict.

### Symbol Table Ordering

The first symbol must be the null symbol.

Local symbols must appear before global and weak symbols.

The example emits:

| Index | Binding | Type | Section |
|---:|---|---|---|
| `0` | local | none | undefined |
| `1` | local | section | `.text` |
| `2` | local | section | `.data` |
| `3` | local | section | `.bss` |
| `4` | global | function | `.text` |
| `5` | global | object | `.bss` |
| `6` | global | function | undefined |

The `.symtab` section header stores:

```text
sh_link = index of .strtab
sh_info = index of the first non-local symbol
```

For this table:

```text
sh_link = 6
sh_info = 4
```

An undefined symbol uses:

```text
st_shndx = SHN_UNDEF
st_value = 0
```

The linker resolves it from another object or library.

### Symbol Values Are Section-Relative

In an `ET_REL` object, a defined symbol's value is relative to its section.

For a function:

```text
st_shndx = text section index
st_value = function_label - text_start
st_size  = function size
```

For an object in BSS:

```text
st_shndx = bss section index
st_value = object_label - bss_start
st_size  = object size
```

The linker chooses final virtual addresses later.

Do not write executable-style virtual addresses into ordinary relocatable
symbol values.

### Two String Tables

ELF objects normally contain two different string tables.

`.strtab` stores symbol names:

```text
\0_start\0scratch\0helper\0
```

`.shstrtab` stores section names:

```text
\0.text\0.data\0.bss\0.rela.text\0.symtab\0...
```

All name fields are byte offsets into the corresponding table:

```text
symbol st_name -> .strtab
section sh_name -> .shstrtab
```

Offset zero represents an empty name.

Section symbols usually use an empty symbol name because the section header
already provides the section's name.

### Relocation Sections Link Two Other Tables

A relocation section must identify:

1. the symbol table used by its relocation records;
2. the section whose fields will be rewritten.

For `.rela.text`:

```text
sh_link = index of .symtab
sh_info = index of .text
```

The same relationship applies to `.rel.text`.

The relocation row's `r_offset` is relative to the target section, not a file
offset:

```text
r_offset = relocation_field - text_start
```

The `_at` helpers calculate this section-relative offset:

```text
elfobj_rela64_x86_64_pc32_at(...)
elfobj_rel32_386_pc32_at(...)
```

The symbol index still belongs to the caller's explicit symbol plan.

### RELA Stores the Addend in the Record

An ELF64 `RELA` row contains:

```text
r_offset
r_info
r_addend
```

For a 32-bit PC-relative x86-64 field, the linker applies:

```text
S + A - P
```

where:

```text
S = resolved symbol value
A = relocation addend
P = address of the relocated field
```

The instruction displacement is relative to the byte after its four-byte
field. Therefore the example uses:

```text
A = -4
```

represented as:

```text
0xfffffffffffffffc
```

The placeholder field itself can remain zero because the addend is stored in
the `RELA` row.

### REL Stores the Addend in the Field

An ELF32 `REL` row contains only:

```text
r_offset
r_info
```

The addend is read from the relocated bytes.

For an i386 PC-relative call:

```text
dd(0xfffffffc)
```

places `-4` in the displacement field before the relocation is applied.

For an absolute `R_386_32` relocation with no additional offset:

```text
dd(0)
```

provides addend zero.

Changing a `REL` placeholder changes the relocation result. It is not merely
unused padding.

### Emit Relocation Fields Deliberately

When constructing an object directly, the source emits the instruction opcode
and relocation field separately:

```text
opcode bytes
label at the relocation field
placeholder bytes
```

The relocation table then describes that field.

This avoids resolving the reference as an ordinary final-image fixup. The
linker, not the assembler, must own unresolved object references.

### Complete ELF64 Object

The following object contains:

- `.text`, `.data`, and `.bss`;
- four `RELA` records;
- local section symbols;
- a global `_start` function;
- a global BSS object named `scratch`;
- an undefined function named `helper`;
- a non-executable stack declaration.

The linked program passes `41` to `helper`, stores the returned `42` in BSS,
loads it back, and exits with the difference from `42`.

```asm
import("format/elfobj.inc");

const section_count: u16 = 9
const shstrndx: u16 = 7
const symbol_count: u64 = 7

const text_index: u64 = 1
const data_index: u64 = 2
const bss_index: u64 = 3
const rela_text_index: u64 = 4
const symtab_index: u64 = 5
const strtab_index: u64 = 6
const first_global_symbol_index: u64 = 4
const helper_symbol_index: u64 = 6

const sh_name_text: u64 = 1
const sh_name_data: u64 = 7
const sh_name_bss: u64 = 13
const sh_name_rela_text: u64 = 18
const sh_name_symtab: u64 = 29
const sh_name_strtab: u64 = 37
const sh_name_shstrtab: u64 = 45
const sh_name_gnu_stack: u64 = 55

const str_name_start: u64 = 1
const str_name_scratch: u64 = 8
const str_name_helper: u64 = 16
const strtab_size: u64 = 23
const shstrtab_size: u64 = 71

const text_foa: u64 = elfobj_align_up(elfobj_header64_size, 16)
const text_size: u64 = 35
const data_foa: u64 = elfobj_align_up(text_foa + text_size, 4)
const data_size: u64 = 4
const bss_foa: u64 = data_foa + data_size
const bss_size: u64 = 64
const rela_text_foa: u64 = elfobj_align_up(bss_foa, 8)
const rela_text_size: u64 = 4 * elfobj_rela64_size
const symtab_foa: u64 = elfobj_align_up(rela_text_foa + rela_text_size, 8)
const symtab_size: u64 = symbol_count * elfobj_sym64_size
const strtab_foa: u64 = symtab_foa + symtab_size
const shstrtab_foa: u64 = strtab_foa + strtab_size
const section_table_foa: u64 = elfobj_align_up(shstrtab_foa + shstrtab_size, 8)

elfobj_begin64(
    section_count,
    section_table_foa,
    shstrndx
);

elfobj_begin_section(".text", text_foa);
text_start:
_start:
    db(0x8b, 0x3d);
rel_data:
    dd(0);
    db(0xe8);
rel_helper:
    dd(0);
    db(0x89, 0x05);
rel_scratch_store:
    dd(0);
    db(0x8b, 0x05);
rel_scratch_load:
    dd(0);
    db(0x83, 0xe8, 42);
    db(0x89, 0xc7);
    mov eax, 60
    syscall
text_end:
elfobj_end_section(text_size);

elfobj_begin_section(".data", data_foa);
data_start:
    dd(41);
data_end:
elfobj_end_section(data_size);

region.begin(".bss", 0, bss_foa);
bss_start:
scratch:
    reserve(bss_size);
bss_end:
region.file_align(1);

region.begin(
    ".rela.text",
    rela_text_foa,
    rela_text_foa
);
rela_start:
elfobj_rela64_x86_64_pc32_at(
    text_start,
    rel_data,
    data_index,
    0xfffffffffffffffc
);
elfobj_rela64_x86_64_plt32_at(
    text_start,
    rel_helper,
    helper_symbol_index,
    0xfffffffffffffffc
);
elfobj_rela64_x86_64_pc32_at(
    text_start,
    rel_scratch_store,
    bss_index,
    0xfffffffffffffffc
);
elfobj_rela64_x86_64_pc32_at(
    text_start,
    rel_scratch_load,
    bss_index,
    0xfffffffffffffffc
);
rela_end:

region.begin(".symtab", symtab_foa, symtab_foa);
elfobj_sym64(0, 0, elf_shn_undef, 0, 0);
elfobj_sym64(
    0,
    elfobj_st_info(elfobj_stb_local, elfobj_stt_section),
    text_index,
    0,
    0
);
elfobj_sym64(
    0,
    elfobj_st_info(elfobj_stb_local, elfobj_stt_section),
    data_index,
    0,
    0
);
elfobj_sym64(
    0,
    elfobj_st_info(elfobj_stb_local, elfobj_stt_section),
    bss_index,
    0,
    0
);
elfobj_sym64(
    str_name_start,
    elfobj_st_info(elfobj_stb_global, elfobj_stt_func),
    text_index,
    0,
    text_size
);
elfobj_sym64(
    str_name_scratch,
    elfobj_st_info(elfobj_stb_global, elfobj_stt_object),
    bss_index,
    0,
    bss_size
);
elfobj_sym64(
    str_name_helper,
    elfobj_st_info(elfobj_stb_global, elfobj_stt_func),
    elf_shn_undef,
    0,
    0
);

region.begin(".strtab", strtab_foa, strtab_foa);
db(0, "_start", 0, "scratch", 0, "helper", 0);

region.begin(
    ".shstrtab",
    shstrtab_foa,
    shstrtab_foa
);
db(
    0,
    ".text", 0,
    ".data", 0,
    ".bss", 0,
    ".rela.text", 0,
    ".symtab", 0,
    ".strtab", 0,
    ".shstrtab", 0,
    ".note.GNU-stack", 0
);

region.begin(
    ".shdr",
    section_table_foa,
    section_table_foa
);
elfobj_shdr64(
    0,
    elf_sht_null,
    0,
    0,
    0,
    0,
    0,
    0,
    0
);
elfobj_shdr64(
    sh_name_text,
    elf_sht_progbits,
    elf_shf_alloc | elf_shf_execinstr,
    text_foa,
    text_size,
    0,
    0,
    16,
    0
);
elfobj_shdr64(
    sh_name_data,
    elf_sht_progbits,
    elf_shf_alloc | elf_shf_write,
    data_foa,
    data_size,
    0,
    0,
    4,
    0
);
elfobj_shdr64(
    sh_name_bss,
    elf_sht_nobits,
    elf_shf_alloc | elf_shf_write,
    bss_foa,
    bss_size,
    0,
    0,
    4,
    0
);
elfobj_shdr64(
    sh_name_rela_text,
    elf_sht_rela,
    0,
    rela_text_foa,
    rela_text_size,
    symtab_index,
    text_index,
    8,
    elfobj_rela64_size
);
elfobj_shdr64(
    sh_name_symtab,
    elf_sht_symtab,
    0,
    symtab_foa,
    symtab_size,
    strtab_index,
    first_global_symbol_index,
    8,
    elfobj_sym64_size
);
elfobj_shdr64(
    sh_name_strtab,
    elf_sht_strtab,
    0,
    strtab_foa,
    strtab_size,
    0,
    0,
    1,
    0
);
elfobj_shdr64(
    sh_name_shstrtab,
    elf_sht_strtab,
    0,
    shstrtab_foa,
    shstrtab_size,
    0,
    0,
    1,
    0
);
elfobj_shdr64(
    sh_name_gnu_stack,
    elf_sht_progbits,
    0,
    0,
    0,
    0,
    0,
    1,
    0
);

defer {
    assert(region_file_size(bss_start) == 0);
    assert(bss_end - bss_start == bss_size);
    assert(
        elfobj64_rela_count(rela_start, rela_end) == 4
    );
}
```

The external function can be supplied by another object:

```c
int helper(int value) {
    return value + 1;
}
```

Both objects must use the same target architecture and calling convention.

The linked program exits with status zero only when:

- the undefined `helper` symbol resolves;
- the data relocation loads `41`;
- the call relocation reaches `helper`;
- the BSS relocation stores `42`;
- the second BSS relocation loads `42` back.

### Resulting ELF64 Layout

The direct object is 1040 bytes.

Its section layout is:

| Section | FOA | File size | Logical size |
|---|---:|---:|---:|
| `.text` | `64` | `35` | `35` |
| `.data` | `100` | `4` | `4` |
| `.bss` | `104` | `0` | `64` |
| `.rela.text` | `104` | `96` | `96` |
| `.symtab` | `200` | `168` | `168` |
| `.strtab` | `368` | `23` | `23` |
| `.shstrtab` | `391` | `71` | `71` |
| section headers | `464` | `576` | `576` |

The final size is explained by real records:

```text
9 section headers * 64 bytes = 576 bytes
7 symbols * 24 bytes         = 168 bytes
4 RELA rows * 24 bytes       = 96 bytes
```

There is no virtual-page-sized file hole, and the 64 BSS bytes are not stored.

The four relocation rows are:

| Offset | Type | Symbol | Addend |
|---:|---|---|---:|
| `2` | `R_X86_64_PC32` | `.data` | `-4` |
| `7` | `R_X86_64_PLT32` | `helper` | `-4` |
| `13` | `R_X86_64_PC32` | `.bss` | `-4` |
| `19` | `R_X86_64_PC32` | `.bss` | `-4` |

### ELF32 Uses REL

The ELF32 object uses the same section and symbol plan.

Its important differences are:

| ELF64 | ELF32 |
|---|---|
| `elfobj_begin64` | `elfobj_begin32` |
| `elfobj_shdr64` | `elfobj_shdr32` |
| `elfobj_sym64` | `elfobj_sym32` |
| `.rela.text` | `.rel.text` |
| `SHT_RELA` | `SHT_REL` |
| 24-byte relocation rows | 8-byte relocation rows |
| addend in row | addend in relocated field |
| `R_X86_64_PC32` | `R_386_PC32` |
| `R_X86_64_PLT32` | `R_386_PC32` |
| `R_X86_64_PC32` for data | `R_386_32` for absolute data |

For the external call field:

```text
rel_helper:
    dd(0xfffffffc)
```

the field stores addend `-4`.

The corresponding relocation is:

```text
elfobj_rel32_386_pc32_at(
    text_start,
    rel_helper,
    helper_symbol_index
)
```

The ELF32 object is 704 bytes.

Its layout is:

| Section | FOA | File size | Logical size |
|---|---:|---:|---:|
| `.text` | `64` | `36` | `36` |
| `.data` | `100` | `4` | `4` |
| `.bss` | `104` | `0` | `64` |
| `.rel.text` | `104` | `32` | `32` |
| `.symtab` | `136` | `112` | `112` |
| `.strtab` | `248` | `23` | `23` |
| `.shstrtab` | `271` | `70` | `70` |
| section headers | `344` | `360` | `360` |

It contains four relocations:

| Offset | Type | Symbol |
|---:|---|---|
| `2` | `R_386_32` | `.data` |
| `7` | `R_386_PC32` | `helper` |
| `15` | `R_386_32` | `.bss` |
| `20` | `R_386_32` | `.bss` |

The linked 32-bit program follows the i386 calling convention:

- push the argument before the call;
- remove the argument from the stack after the call;
- use the 32-bit process-exit system call.

### Deferred Header Patching

The direct layer also provides:

```text
elfobj_begin64_deferred()
elfobj_patch_header64(...)

elfobj_begin32_deferred()
elfobj_patch_header32(...)
```

Use these when the final section-table FOA, section count, or section-name
table index is not known when the ELF header is first emitted.

The deferred patch changes existing header fields only. It does not generate
section rows, symbols, string tables, or relocation records.

The caller remains responsible for reserving and emitting every required
record.

### Direct ELF Object Checklist

Before accepting a direct ELF object, confirm:

1. The ELF class matches the instruction mode.
2. The machine matches the emitted instructions.
3. The file type is `ET_REL`.
4. The program-header fields are zero.
5. Section index zero is the null row.
6. `e_shoff`, `e_shnum`, and `e_shstrndx` describe the final table.
7. Every section name is a valid `.shstrtab` offset.
8. Every symbol name is a valid `.strtab` offset.
9. Local symbols precede global and weak symbols.
10. `.symtab sh_info` identifies the first non-local symbol.
11. `.symtab sh_link` identifies `.strtab`.
12. Each relocation section links to `.symtab`.
13. Each relocation section identifies its target section.
14. Every relocation symbol index exists.
15. Every relocation offset lies inside its target section.
16. RELA addends are stored in relocation rows.
17. REL addends are stored in relocated fields.
18. BSS uses `SHT_NOBITS` and has zero physical size.
19. BSS logical size and symbol sizes remain correct.
20. `.note.GNU-stack` does not request executable stack permission.
21. The object is accepted by an independent object reader.
22. The object links with another object that provides undefined symbols.
23. The linked program exercises the relocated data, call, and BSS fields.

Chapter 11 continues direct ELF construction with shared objects and dynamic
metadata.

## 11. Direct ELF Shared Objects and Dynamic Metadata

An ELF shared object is an `ET_DYN` image that exposes symbols to a loader and
may request symbols from other loaded objects.

At the direct layer, the caller constructs all of the loader-visible records:

- the ELF header;
- every program-header row;
- every allocated section;
- the dynamic symbol and string tables;
- the hash table;
- relocation records;
- the dynamic table;
- section headers and their string table.

The direct helpers emit those records. They do not choose a permission model,
assign program-header rows, separate file offsets from virtual addresses, or
decide which dynamic tags are required.

### Shared Objects Use Both Program and Section Headers

Program headers describe the memory image consumed by the loader.

Section headers describe named records used by linkers, debuggers, object
readers, and other tooling.

A direct shared-object plan therefore has two related views:

| View | Records |
|---|---|
| runtime image | `PT_LOAD`, `PT_DYNAMIC`, permissions, virtual addresses |
| named metadata | `.dynsym`, `.dynstr`, `.hash`, `.rela.plt`, `.dynamic` |

The program-header table is authoritative for loading.

The section-header table must still agree with the same bytes:

```text
section sh_offset -> physical file position
section sh_addr   -> runtime virtual address
```

An allocated section normally has both values.

They are not interchangeable.

### Use Separate File and Runtime Coordinates

The compact file and the runtime image serve different purposes.

The file should contain adjacent records with only the padding required by
their record alignment:

```text
ELF header
program headers
code
PLT
GOT and dynamic metadata
section-name strings
section headers
```

The runtime image should separate incompatible permissions by virtual page:

```text
RX header and code
RX PLT
RW GOT and dynamic metadata
```

The file does not need a physical 4 KiB hole between those mappings.

For every `PT_LOAD` row:

```text
p_vaddr % p_align == p_offset % p_align
```

A later mapping can therefore use a compact FOA and a higher congruent virtual
address.

The examples in this chapter use:

```text
next_vaddr =
    align_up(previous_logical_end, page_size)
    + next_foa % page_size
```

This preserves page congruence without storing virtual padding in the file.

### Do Not Map the Whole File as RWX

A single readable, writable, executable `PT_LOAD` row is easy to construct,
but it grants write permission to code and execute permission to writable
metadata.

Use separate rows instead:

| Content | Flags |
|---|---|
| ELF header, PHDR table, code | `PF_R \| PF_X` |
| PLT | `PF_R \| PF_X` |
| GOT, dynamic tables, relocations | `PF_R \| PF_W` |
| `PT_DYNAMIC` view | `PF_R \| PF_W` |

An export-only object does not require a PLT row.

An importing object normally benefits from a dedicated PLT row because its
GOT and dynamic records must be writable while its PLT must remain executable.

### Dynamic Table Addresses Are Virtual Addresses

The dynamic loader interprets address-valued tags in runtime address space.

Examples include:

```text
DT_HASH
DT_STRTAB
DT_SYMTAB
DT_PLTGOT
DT_JMPREL
DT_RELA
```

Their values are not file offsets.

Size and index tags have different meanings:

```text
DT_STRSZ   -> byte count
DT_SYMENT  -> symbol-record size
DT_RELASZ  -> relocation-table byte count
DT_RELAENT -> relocation-record size
DT_NEEDED  -> byte offset inside .dynstr
DT_SONAME  -> byte offset inside .dynstr
```

The direct export and import emitters accept runtime virtual addresses for
address-valued entries.

Pass FOAs only to fields that explicitly describe physical file positions.

### Direct Shared-Object Helpers

The shared-object family is split into three direct includes:

```text
format/elfso.inc
format/elf_export.inc
format/elfso_import.inc
```

`elfso.inc` provides the common records:

```text
elfso_begin64
elfso_phdr64
elfso_shdr64
elfso_sym64
elfso_dyn64
elfso_finalize_phdr64
elfso_finalize_load64
```

`elf_export.inc` provides export lists and generated export metadata:

```text
elf_export_new
elf_export_use64
elf_export_use64_many
elf_export_use64_pairs
elf_export_emit_dynsym64
elf_export_emit_dynstr64
elf_export_emit_dynamic64
elf_export_hash
```

`elfso_import.inc` provides import declarations, PLT and GOT emitters,
relocations, and dynamic entries:

```text
elfso_import_new
elfso_import_use64_many
elfso_import_use64_pairs
elfso_import_use64_plt_many
elfso_import_use64_plt_as
elfso_import_emit_plt64
elfso_import_emit_gotplt64
elfso_import_emit_dynsym64
elfso_import_emit_rela_plt64
elfso_import_emit_dynamic64_plt
```

The direct caller still chooses all indexes, table positions, and
program-header rows.

### Identity-Mapped Convenience Helpers

Two common helpers assume that a region's logical address equals its FOA:

```text
elfso_begin_region(name, file_offset)
elfso_finalize_dynamic64(row, dynamic_offset, size)
```

They are suitable only when that identity is intentional.

For a compact file with separated virtual mappings, use:

```text
region.begin(name, virtual_address, file_offset)
```

and emit the `PT_DYNAMIC` row with:

```text
elfso_finalize_phdr64(
    row,
    elf_pt_dynamic,
    elf_pf_r | elf_pf_w,
    dynamic_foa,
    dynamic_vaddr,
    dynamic_size,
    dynamic_size,
    8
);
```

This preserves the distinct physical and logical coordinates.

### Export-Only Shared Object

The following ELF64 shared object exports two functions.

It uses three program-header rows:

1. an RX mapping for the header, program headers, and code;
2. an RW mapping for allocated dynamic metadata;
3. a `PT_DYNAMIC` view into the RW mapping.

```asm
import("format/elf_export.inc");

const ph_count: u16 = 3
const section_count: u16 = 7
const shstrndx: u16 = 6

const text_index: u64 = 1
const dynsym_index: u64 = 2
const dynstr_index: u64 = 3
const hash_index: u64 = 4
const dynamic_index: u64 = 5

const sh_name_text: u64 = 1
const sh_name_dynsym: u64 = 7
const sh_name_dynstr: u64 = 15
const sh_name_hash: u64 = 23
const sh_name_dynamic: u64 = 29
const sh_name_shstrtab: u64 = 38

const text_foa: u64 = elfso_align_up(
    elfso_header64_size + ph_count * elfso_phdr64_size,
    16
)
const export_size: u64 = 4
const text_size: u64 = export_size * 2

let exports: list = elf_export_new()
exports = elf_export_use64(
    exports,
    "x_add7",
    "x_add7",
    text_index,
    export_size
)
exports = elf_export_use64(
    exports,
    "x_sub3",
    "x_sub3",
    text_index,
    export_size
)

const soname: string = "libdirect_export.so"
const dynstr_first_export: u64 = 1
const dynstr_soname: u64 = dynstr_first_export + elf_export_names_size(exports)
const dynstr_size: u64 = elf_export_dynstr_size(exports, soname)
const shstrtab_size: u64 = 48

const dynsym_foa: u64 = elfso_align_up(text_foa + text_size, 8)
const metadata_foa: u64 = dynsym_foa
const metadata_page: u64 = elfso_align_up(
    text_foa + text_size,
    elf_default_page_align
)
const metadata_vaddr: u64 = metadata_page + metadata_foa % elf_default_page_align
const dynsym_size: u64 = (len(exports) + 1) * elfso_sym64_size
const dynstr_foa: u64 = dynsym_foa + dynsym_size
const hash_foa: u64 = elfso_align_up(dynstr_foa + dynstr_size, 4)
const hash_size: u64 = elf_export_hash_size(exports)
const dynamic_foa: u64 = elfso_align_up(hash_foa + hash_size, 8)
const dynamic_size: u64 = 7 * elfso_dyn64_size
const shstrtab_foa: u64 = dynamic_foa + dynamic_size
const section_table_foa: u64 = elfso_align_up(
    shstrtab_foa + shstrtab_size,
    8
)
const file_size: u64 = section_table_foa + section_count * elfso_shdr64_size

const dynsym_vaddr: u64 = metadata_vaddr + dynsym_foa - metadata_foa
const dynstr_vaddr: u64 = metadata_vaddr + dynstr_foa - metadata_foa
const hash_vaddr: u64 = metadata_vaddr + hash_foa - metadata_foa
const dynamic_vaddr: u64 = metadata_vaddr + dynamic_foa - metadata_foa
const metadata_size: u64 = dynamic_foa + dynamic_size - metadata_foa

elfso_begin64(
    ph_count,
    section_table_foa,
    section_count,
    shstrndx
);

elfso_begin_region(".text", text_foa);
text_start:
x_add7:
    db(0x8d, 0x47, 0x07, 0xc3);
x_sub3:
    db(0x8d, 0x47, 0xfd, 0xc3);
text_end:
elfso_end_region(text_size);

region.begin(".metadata", metadata_vaddr, metadata_foa);

assert(file_cursor_real() == dynsym_foa);
elf_export_emit_dynsym64(exports, dynstr_first_export);

assert(file_cursor_real() == dynstr_foa);
elf_export_emit_dynstr64(exports, soname);

align(4);
assert(file_cursor_real() == hash_foa);
elf_export_hash(exports);

align(8);
assert(file_cursor_real() == dynamic_foa);
elf_export_emit_dynamic64(
    dynstr_vaddr,
    dynstr_size,
    dynsym_vaddr,
    hash_vaddr,
    dynstr_soname
);

assert(file_cursor_real() == shstrtab_foa);
db(
    0,
    ".text", 0,
    ".dynsym", 0,
    ".dynstr", 0,
    ".hash", 0,
    ".dynamic", 0,
    ".shstrtab", 0
);

align(8);
assert(file_cursor_real() == section_table_foa);

elfso_shdr64(
    0,
    elf_sht_null,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
);
elfso_shdr64(
    sh_name_text,
    elf_sht_progbits,
    elf_shf_alloc | elf_shf_execinstr,
    text_foa,
    text_foa,
    text_end - text_start,
    0,
    0,
    16,
    0
);
elfso_shdr64(
    sh_name_dynsym,
    elf_sht_dynsym,
    elf_shf_alloc,
    dynsym_vaddr,
    dynsym_foa,
    dynsym_size,
    dynstr_index,
    1,
    8,
    elfso_sym64_size
);
elfso_shdr64(
    sh_name_dynstr,
    elf_sht_strtab,
    elf_shf_alloc,
    dynstr_vaddr,
    dynstr_foa,
    dynstr_size,
    0,
    0,
    1,
    0
);
elfso_shdr64(
    sh_name_hash,
    elf_sht_hash,
    elf_shf_alloc,
    hash_vaddr,
    hash_foa,
    hash_size,
    dynsym_index,
    0,
    4,
    4
);
elfso_shdr64(
    sh_name_dynamic,
    elf_sht_dynamic,
    elf_shf_alloc | elf_shf_write,
    dynamic_vaddr,
    dynamic_foa,
    dynamic_size,
    dynstr_index,
    0,
    8,
    elfso_dyn64_size
);
elfso_shdr64(
    sh_name_shstrtab,
    elf_sht_strtab,
    0,
    0,
    shstrtab_foa,
    shstrtab_size,
    0,
    0,
    1,
    0
);

region.file_align(1);

elfso_finalize_load64(
    0,
    0,
    0,
    text_foa + text_size,
    text_foa + text_size,
    elf_pf_r | elf_pf_x
);
elfso_finalize_load64(
    1,
    metadata_foa,
    metadata_vaddr,
    metadata_size,
    metadata_size,
    elf_pf_r | elf_pf_w
);
elfso_finalize_phdr64(
    2,
    elf_pt_dynamic,
    elf_pf_r | elf_pf_w,
    dynamic_foa,
    dynamic_vaddr,
    dynamic_size,
    dynamic_size,
    8
);
```

The output is 992 bytes.

Its runtime mappings are:

| Row | Type | FOA | VA | Size | Flags |
|---:|---|---:|---:|---:|---|
| 0 | `PT_LOAD` | `0x000` | `0x0000` | `0x0f8` | RX |
| 1 | `PT_LOAD` | `0x0f8` | `0x10f8` | `0x0f8` | RW |
| 2 | `PT_DYNAMIC` | `0x180` | `0x1180` | `0x070` | RW |

The physical file stays contiguous.

The metadata mapping is one virtual page above the code mapping and remains
page-congruent with its FOA.

### Export Symbols and Hash Chains

The dynamic symbol table begins with the mandatory null symbol.

The two exported symbols follow:

| Index | Name | Value | Size | Section |
|---:|---|---:|---:|---:|
| 0 | null | `0` | `0` | `SHN_UNDEF` |
| 1 | `x_add7` | `0xf0` | `4` | 1 |
| 2 | `x_sub3` | `0xf4` | `4` | 1 |

For a shared object, each defined symbol value is its runtime virtual address.

The code mapping begins at zero, so the code VAs happen to equal their FOAs in
this example.

That identity does not extend to the metadata mapping.

The System V hash table contains:

```text
nbucket = 1
nchain  = symbol count
bucket[0] -> first exported symbol
chain rows -> remaining exported symbols
```

Every hash index refers to a dynamic-symbol index.

It does not refer to a section index or string offset.

### The Export Dynamic Table

The export-only dynamic table contains:

| Tag | Value kind |
|---|---|
| `DT_HASH` | VA of `.hash` |
| `DT_STRTAB` | VA of `.dynstr` |
| `DT_STRSZ` | byte size of `.dynstr` |
| `DT_SYMTAB` | VA of `.dynsym` |
| `DT_SYMENT` | 24 |
| `DT_SONAME` | byte offset inside `.dynstr` |
| `DT_NULL` | 0 |

The `PT_DYNAMIC` row points to the same bytes as the `.dynamic` section:

```text
p_offset == .dynamic sh_offset
p_vaddr  == .dynamic sh_addr
p_filesz == .dynamic sh_size
```

The values are related, but the program-header and section-header records are
still separate records that the direct caller must emit consistently.

### PLT and GOT Responsibilities

A PLT import introduces four connected structures:

```text
.plt
.got.plt
.dynsym and .dynstr
.rela.plt
```

The PLT contains executable resolver stubs.

The GOT contains writable runtime slots.

The relocation table tells the loader which symbol should populate each slot.

The dynamic table connects the loader to those records.

The direct import helper uses x86-64 PLT entries:

```text
PLT0                 -> resolver entry
one 16-byte row      -> each imported function
one 8-byte GOT slot  -> each imported function
one 24-byte RELA row -> each imported function
```

The PLT and GOT may be on different virtual pages.

Their relative branch and memory displacements must therefore be computed from
virtual addresses, not FOAs.

Pass runtime addresses to:

```text
elfso_import_emit_plt64
elfso_import_emit_gotplt64
```

The physical placement is controlled separately by `region.begin`.

### Dynamic Symbols for Imports and Exports

The dynamic symbol ordering in the importing example is:

| Index | Symbol | Definition |
|---:|---|---|
| 0 | null | reserved |
| 1 | `puts` | undefined import |
| 2 | `exported_call_puts` | defined export |

The relocation row stores symbol index `1`.

The hash chain includes both public names.

`.dynsym sh_info` identifies the first global symbol. In this direct layout,
that value is `1`.

### PLT Relocations Use Runtime Slot Addresses

An x86-64 jump-slot relocation is:

```text
r_offset = runtime VA of the GOT slot
r_info   = symbol index and R_X86_64_JUMP_SLOT
r_addend = 0
```

`r_offset` is not the slot's FOA.

The relocation section itself still has a physical file position:

```text
.rela.plt sh_offset -> relocation row FOA
.rela.plt sh_addr   -> relocation row runtime VA
```

The direct caller must plan both values.

### Importing Shared Object

The following shared object exports `exported_call_puts` and imports `puts`
through a PLT entry.

It uses four program-header rows:

1. RX header and text;
2. RX PLT;
3. RW GOT and dynamic metadata;
4. `PT_DYNAMIC` inside the RW mapping.

```asm
import("format/elfso_import.inc");

const imports: list = elfso_import_use64_plt_many(
    elfso_import_new(),
    "libc.so.6",
    list.of("puts")
)

const soname: string = "libdirect_import.so"

const ph_count: u16 = 4
const section_count: u16 = 10
const shstrndx: u16 = 9

const text_index: u64 = 1
const plt_index: u64 = 2
const gotplt_index: u64 = 3
const dynsym_index: u64 = 4
const dynstr_index: u64 = 5
const hash_index: u64 = 6
const rela_plt_index: u64 = 7
const dynamic_index: u64 = 8

const sh_name_text: u64 = 1
const sh_name_plt: u64 = 7
const sh_name_gotplt: u64 = 12
const sh_name_dynsym: u64 = 21
const sh_name_dynstr: u64 = 29
const sh_name_hash: u64 = 37
const sh_name_rela_plt: u64 = 43
const sh_name_dynamic: u64 = 53
const sh_name_shstrtab: u64 = 62

const import_count: u64 = len(imports)
const first_import_symbol: u64 = 1
const exported_symbol: u64 = first_import_symbol + import_count
const exported_name: string = "exported_call_puts"

const text_foa: u64 = elfso_align_up(
    elfso_header64_size + ph_count * elfso_phdr64_size,
    16
)
const text_size: u64 = 32
const plt_foa: u64 = elfso_align_up(text_foa + text_size, 16)
const plt_size: u64 = elfso_import_plt_size(imports)
const gotplt_foa: u64 = elfso_align_up(plt_foa + plt_size, 8)
const gotplt_size: u64 = elfso_import_gotplt_size(imports)
const dynsym_foa: u64 = elfso_align_up(gotplt_foa + gotplt_size, 8)
const dynsym_size: u64 = (1 + import_count + 1) * elfso_sym64_size
const dynstr_foa: u64 = dynsym_foa + dynsym_size
const import_dynstr_size: u64 = elfso_import_dynstr_size(imports, soname)
const dynstr_size: u64 = import_dynstr_size + len(exported_name) + 1
const hash_foa: u64 = elfso_align_up(dynstr_foa + dynstr_size, 4)
const hash_size: u64 = 24
const rela_plt_foa: u64 = elfso_align_up(hash_foa + hash_size, 8)
const rela_plt_size: u64 = elfso_import_rela_plt_size(imports)
const dynamic_foa: u64 = elfso_align_up(
    rela_plt_foa + rela_plt_size,
    8
)
const dynamic_size: u64 = elfso_import_dynamic_plt_size(imports)
const shstrtab_foa: u64 = dynamic_foa + dynamic_size
const shstrtab_size: u64 = 72
const section_table_foa: u64 = elfso_align_up(
    shstrtab_foa + shstrtab_size,
    8
)
const file_size: u64 = section_table_foa + section_count * elfso_shdr64_size

const plt_page: u64 = elfso_align_up(
    text_foa + text_size,
    elf_default_page_align
)
const plt_vaddr: u64 = plt_page + plt_foa % elf_default_page_align
const metadata_foa: u64 = gotplt_foa
const metadata_page: u64 = elfso_align_up(
    plt_vaddr + plt_size,
    elf_default_page_align
)
const metadata_vaddr: u64 = metadata_page + metadata_foa % elf_default_page_align
const gotplt_vaddr: u64 = metadata_vaddr
const dynsym_vaddr: u64 = metadata_vaddr + dynsym_foa - metadata_foa
const dynstr_vaddr: u64 = metadata_vaddr + dynstr_foa - metadata_foa
const hash_vaddr: u64 = metadata_vaddr + hash_foa - metadata_foa
const rela_plt_vaddr: u64 = metadata_vaddr + rela_plt_foa - metadata_foa
const dynamic_vaddr: u64 = metadata_vaddr + dynamic_foa - metadata_foa
const metadata_size: u64 = dynamic_foa + dynamic_size - metadata_foa

const dynstr_name_start: u64 = 1
const dynstr_exported: u64 = dynstr_name_start + elfso_import_names_size(imports)
const dynstr_soname: u64 = dynstr_exported + len(exported_name) + 1
const dynstr_needed_start: u64 = dynstr_soname + len(soname) + 1

elfso_begin64(
    ph_count,
    section_table_foa,
    section_count,
    shstrndx
);

elfso_begin_region(".text", text_foa);
exported_call_puts:
    lea rdi, [rel message_text]
    call puts_plt
    ret
message_text:
    db("xirasm import slot", 0);
elfso_end_region(text_size);

region.begin(".plt", plt_vaddr, plt_foa);
elfso_import_emit_plt64(
    imports,
    plt_vaddr,
    gotplt_vaddr
);
region.file_align(1);

region.begin(".metadata", metadata_vaddr, metadata_foa);
elfso_import_emit_gotplt64(
    imports,
    dynamic_vaddr,
    plt_vaddr
);

align(8);
assert(file_cursor_real() == dynsym_foa);
elfso_import_emit_dynsym64(
    imports,
    dynstr_name_start
);
elfso_sym64(
    dynstr_exported,
    elfso_st_info(elf_stb_global, elf_stt_func),
    text_index,
    exported_call_puts,
    text_size
);

assert(file_cursor_real() == dynstr_foa);
db(
    0,
    "puts", 0,
    exported_name, 0,
    soname, 0,
    "libc.so.6", 0
);

align(4);
assert(file_cursor_real() == hash_foa);
dd(1);
dd(exported_symbol + 1);
dd(first_import_symbol);
dd(0);
dd(exported_symbol);
dd(0);

align(8);
assert(file_cursor_real() == rela_plt_foa);
elfso_import_emit_rela_plt64(
    imports,
    first_import_symbol
);

assert(file_cursor_real() == dynamic_foa);
elfso_import_emit_dynamic64_plt(
    imports,
    dynstr_vaddr,
    dynstr_size,
    dynsym_vaddr,
    hash_vaddr,
    gotplt_vaddr,
    rela_plt_vaddr,
    rela_plt_size,
    dynstr_needed_start
);

assert(file_cursor_real() == shstrtab_foa);
db(
    0,
    ".text", 0,
    ".plt", 0,
    ".got.plt", 0,
    ".dynsym", 0,
    ".dynstr", 0,
    ".hash", 0,
    ".rela.plt", 0,
    ".dynamic", 0,
    ".shstrtab", 0
);

align(8);
assert(file_cursor_real() == section_table_foa);

elfso_shdr64(
    0,
    elf_sht_null,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
);
elfso_shdr64(
    sh_name_text,
    elf_sht_progbits,
    elf_shf_alloc | elf_shf_execinstr,
    text_foa,
    text_foa,
    text_size,
    0,
    0,
    16,
    0
);
elfso_shdr64(
    sh_name_plt,
    elf_sht_progbits,
    elf_shf_alloc | elf_shf_execinstr,
    plt_vaddr,
    plt_foa,
    plt_size,
    0,
    0,
    16,
    elfso_import_plt_entry_size
);
elfso_shdr64(
    sh_name_gotplt,
    elf_sht_progbits,
    elf_shf_alloc | elf_shf_write,
    gotplt_vaddr,
    gotplt_foa,
    gotplt_size,
    0,
    0,
    8,
    elfso_import_gotplt_entry_size
);
elfso_shdr64(
    sh_name_dynsym,
    elf_sht_dynsym,
    elf_shf_alloc,
    dynsym_vaddr,
    dynsym_foa,
    dynsym_size,
    dynstr_index,
    first_import_symbol,
    8,
    elfso_sym64_size
);
elfso_shdr64(
    sh_name_dynstr,
    elf_sht_strtab,
    elf_shf_alloc,
    dynstr_vaddr,
    dynstr_foa,
    dynstr_size,
    0,
    0,
    1,
    0
);
elfso_shdr64(
    sh_name_hash,
    elf_sht_hash,
    elf_shf_alloc,
    hash_vaddr,
    hash_foa,
    hash_size,
    dynsym_index,
    0,
    4,
    4
);
elfso_shdr64(
    sh_name_rela_plt,
    elf_sht_rela,
    elf_shf_alloc,
    rela_plt_vaddr,
    rela_plt_foa,
    rela_plt_size,
    dynsym_index,
    0,
    8,
    elfso_import_rela64_size
);
elfso_shdr64(
    sh_name_dynamic,
    elf_sht_dynamic,
    elf_shf_alloc | elf_shf_write,
    dynamic_vaddr,
    dynamic_foa,
    dynamic_size,
    dynstr_index,
    0,
    8,
    elfso_dyn64_size
);
elfso_shdr64(
    sh_name_shstrtab,
    elf_sht_strtab,
    0,
    0,
    shstrtab_foa,
    shstrtab_size,
    0,
    0,
    1,
    0
);

region.file_align(1);

elfso_finalize_load64(
    0,
    0,
    0,
    text_foa + text_size,
    text_foa + text_size,
    elf_pf_r | elf_pf_x
);
elfso_finalize_load64(
    1,
    plt_foa,
    plt_vaddr,
    plt_size,
    plt_size,
    elf_pf_r | elf_pf_x
);
elfso_finalize_load64(
    2,
    metadata_foa,
    metadata_vaddr,
    metadata_size,
    metadata_size,
    elf_pf_r | elf_pf_w
);
elfso_finalize_phdr64(
    3,
    elf_pt_dynamic,
    elf_pf_r | elf_pf_w,
    dynamic_foa,
    dynamic_vaddr,
    dynamic_size,
    dynamic_size,
    8
);
```

The output is 1448 bytes.

Its program-header rows are:

| Row | Type | FOA | VA | Size | Flags |
|---:|---|---:|---:|---:|---|
| 0 | `PT_LOAD` | `0x000` | `0x0000` | `0x140` | RX |
| 1 | `PT_LOAD` | `0x140` | `0x1140` | `0x020` | RX |
| 2 | `PT_LOAD` | `0x160` | `0x2160` | `0x180` | RW |
| 3 | `PT_DYNAMIC` | `0x230` | `0x2230` | `0x0b0` | RW |

No row has both write and execute permission.

The file positions remain adjacent:

```text
text end    = 0x140
PLT start   = 0x140
PLT end     = 0x160
metadata    = 0x160
```

The virtual addresses occupy separate pages:

```text
text mapping     -> page 0
PLT mapping      -> page 1
metadata mapping -> page 2
```

### Import Dynamic Table

The import example emits these entries:

| Tag | Value |
|---|---|
| `DT_HASH` | VA `0x2200` |
| `DT_STRTAB` | VA `0x21c8` |
| `DT_STRSZ` | 55 |
| `DT_SYMTAB` | VA `0x2180` |
| `DT_SYMENT` | 24 |
| `DT_PLTGOT` | VA `0x2160` |
| `DT_PLTRELSZ` | 24 |
| `DT_PLTREL` | `DT_RELA` |
| `DT_JMPREL` | VA `0x2218` |
| `DT_NEEDED` | `.dynstr` offset 45 |
| `DT_NULL` | 0 |

The numeric equality between a dynamic value and a section's `sh_addr` is
intentional.

It should not equal the section's `sh_offset` once VA and FOA are separated.

### Loading and Calling the Import Example

A native consumer can load the shared object and call its exported function:

```c
#include <dlfcn.h>

typedef int (*entry_fn)(void);

int main(void) {
    void *handle = dlopen("./libdirect_import.so", RTLD_NOW);
    if (handle == 0) {
        return 1;
    }

    entry_fn entry = (entry_fn)dlsym(
        handle,
        "exported_call_puts"
    );
    if (entry == 0) {
        dlclose(handle);
        return 2;
    }

    const int result = entry();
    dlclose(handle);
    return result < 0 ? 3 : 0;
}
```

Successful execution proves more than table readability:

- the loader accepts all program headers;
- the dynamic table contains usable runtime addresses;
- the import symbol resolves;
- the jump-slot relocation writes the GOT slot;
- the PLT reaches the resolved function;
- the exported function is discoverable and callable;
- the permission split does not require an RWX mapping.

### Shared-Object Section Header Rules

Allocated shared-object sections use both coordinates:

| Section | `sh_addr` | `sh_offset` |
|---|---|---|
| `.text` | text VA | text FOA |
| `.plt` | PLT VA | PLT FOA |
| `.got.plt` | GOT VA | GOT FOA |
| `.dynsym` | dynamic-symbol VA | dynamic-symbol FOA |
| `.dynstr` | dynamic-string VA | dynamic-string FOA |
| `.hash` | hash VA | hash FOA |
| `.rela.plt` | relocation VA | relocation FOA |
| `.dynamic` | dynamic-table VA | dynamic-table FOA |

`.shstrtab` is not allocated:

```text
sh_addr = 0
sh_offset = physical string-table position
```

The section-header table itself also does not need to be part of a loadable
mapping.

The examples keep `.shstrtab` and the section-header table in the compact file
after the allocated metadata range.

### Direct Shared-Object Checklist

Before accepting a direct ELF shared object, confirm:

1. The ELF type is `ET_DYN`.
2. The ELF class and machine match the emitted instructions.
3. `e_phoff`, `e_phnum`, and every PHDR row are correct.
4. Every `PT_LOAD` row satisfies page congruence.
5. No `PT_LOAD` row has both write and execute permission.
6. The header and code mapping is readable and executable.
7. The PLT mapping is readable and executable.
8. The GOT and dynamic metadata mapping is readable and writable.
9. File mappings are compact and do not contain virtual-page-sized zero holes.
10. `PT_DYNAMIC` points to the same bytes as `.dynamic`.
11. Every address-valued dynamic tag stores a runtime VA.
12. `DT_NEEDED` and `DT_SONAME` store `.dynstr` byte offsets.
13. Dynamic symbol zero is the null symbol.
14. Imported symbols use `SHN_UNDEF`.
15. Defined exports store runtime virtual addresses.
16. Hash indexes refer to dynamic-symbol indexes.
17. Every jump-slot relocation stores a runtime GOT-slot VA.
18. Every relocation symbol index exists.
19. `.rela.plt sh_link` identifies `.dynsym`.
20. Allocated section headers separate `sh_addr` from `sh_offset`.
21. Non-allocated tables use zero `sh_addr`.
22. The final physical file size is explained by real records and alignment.
23. An independent reader accepts the headers, symbols, and relocations.
24. A real loader can load the export-only object.
25. A real loader can resolve and call the imported function.

The direct shared-object layer is appropriate when the caller needs complete
control over dynamic metadata, permission boundaries, table ordering, or
runtime address assignment.

Use the ordinary format facade when those details are not part of the intended
design.

## 12. Validation and Interoperability

Direct format construction is complete only when the generated file is usable
outside the assembler.

A successful assembly proves that the source was accepted and that all
registered finalizers completed. It does not prove that a loader, linker, or
another language agrees with every field.

Validation therefore has four separate layers:

| Layer | Primary question |
|---|---|
| Structural | Do the bytes describe a valid file of the selected format? |
| Link | Can another object or library consume the file? |
| Load and execute | Can the operating system map and run the result? |
| ABI | Do calls, data, and symbols follow the external contract? |

Each layer catches failures that the previous layer cannot see.

### Validation Is Part of the Layout Plan

Direct helpers expose values that the ordinary facade normally derives:

- header counts;
- row indexes;
- file offsets;
- virtual addresses;
- section and segment sizes;
- symbol indexes;
- string-table offsets;
- relocation targets;
- directory relationships;
- permission flags.

These values should be accompanied by explicit invariants while the layout is
being planned.

For example:

```text
section_table_foa + section_count * section_row_size <= file_size

segment_foa + segment_file_size <= file_size

segment_memory_size >= segment_file_size

virtual_size >= initialized_size

symbol_index < symbol_count

string_offset < string_table_size
```

Do not wait until the entire file has been emitted to decide what makes an
offset or index valid.

The best direct layouts make each relationship visible near the constants that
define it.

### Keep the Four Coordinate Questions Separate

Every allocated range should answer four questions:

1. Where are its bytes in the file?
2. Where are those bytes mapped in memory?
3. How many bytes exist physically?
4. How many bytes exist logically after loading?

These answers may be different.

| Fact | Meaning |
|---|---|
| FOA | Physical position in the file |
| VA or RVA | Runtime location in the loaded image |
| File size | Number of stored bytes |
| Memory size | Number of bytes visible after loading |

A range containing only reserve data may have:

```text
file size   = 0
memory size = nonzero
```

A compact file may place two ranges next to each other physically while mapping
them on different virtual pages.

An independent reader should compare each field with the coordinate system it
belongs to. Numeric equality between FOA and VA is not evidence that the field
uses the correct coordinate.

### Structural Validation

Structural validation reads the generated bytes without relying on labels,
source constants, or helper state.

At minimum, an independent reader should validate:

- format signature and class;
- machine or architecture identifier;
- declared header size;
- table offsets and row counts;
- every row boundary;
- every referenced string;
- every referenced symbol;
- every relocation record;
- every directory range;
- final file size.

The reader should reject truncated input before reading a field.

For each range, validate both addition and multiplication before using the
result:

```text
row_foa = table_foa + row_index * row_size
row_end = row_foa + row_size
```

Both values must remain inside the file.

This matters even when the generator is trusted. A wrong count can make a
correct first row appear to validate while later rows point beyond the file.

### Validate Relationships, Not Only Constants

Checking isolated numbers is not enough.

The following values form relationships:

- a PE data directory and the section containing it;
- a COFF relocation row and its symbol-table entry;
- an ELF relocation section and its linked symbol table;
- a dynamic string offset and the string table size;
- a program header and the bytes it maps;
- an entry point and an executable mapping.

A reader should prove both sides of each relationship.

For example, validating an ELF relocation requires more than checking its type:

```text
relocation target lies inside the intended section
symbol index names an existing symbol
linked section identifies the symbol table
symbol table links to the correct string table
```

Likewise, validating a PE import directory requires following the descriptor,
name, thunk, and hint/name relationships rather than checking only the
directory RVA.

### PE Structural Validation

A direct PE image should be checked in this order:

1. DOS header and PE signature.
2. COFF file header.
3. Optional header.
4. Section table.
5. Data directories.
6. Directory-specific records.
7. Entry point and section permissions.

The section table should satisfy:

```text
PointerToRawData + SizeOfRawData <= file_size

VirtualAddress + VirtualSize <= SizeOfImage

VirtualAddress respects SectionAlignment

PointerToRawData respects FileAlignment when raw data is present
```

Reserve-only tails may increase `VirtualSize` without increasing
`SizeOfRawData`.

Sections with zero raw size should not force a block of physical zero bytes
into the file.

The entry RVA must lie inside an executable section.

Writable data should not be executable unless the image deliberately requires
that permission combination.

### PE Directory Validation

Every nonzero PE data directory should be traced to its records.

For imports, validate:

- descriptor termination;
- DLL name strings;
- lookup-table entries;
- address-table entries;
- ordinal and name forms;
- hint/name strings;
- pointer width.

For exports, validate:

- DLL name;
- ordinal base;
- function count;
- name count;
- address table;
- name-pointer table;
- ordinal table;
- exported RVA values.

For base relocations, validate:

- block page RVA alignment;
- block size;
- entry count derived from block size;
- relocation type for the selected bitness;
- relocation offset within the page;
- complete block coverage.

For resources, validate:

- root-relative directory offsets;
- named and numeric entry ordering;
- language directory levels;
- data-entry RVAs;
- exact payload sizes;
- payload alignment.

For checksums, recompute the checksum from the final file while treating the
checksum field according to the PE algorithm.

Do not validate it from a partially emitted header.

### PE Loader Validation

Structural correctness does not prove that the loader can apply relocations or
resolve imports.

A PE executable should be launched as a separate process.

A PE DLL should be loaded by a native consumer that:

1. opens the library;
2. resolves an exported symbol;
3. calls the symbol;
4. validates its return value or output;
5. unloads the library.

An image with base relocations should also be loaded away from its preferred
base when the environment permits it.

After relocation, every registered relocation slot should equal:

```text
original_value + actual_image_base - preferred_image_base
```

This proves that the relocation directory describes the intended fields, not
merely that the directory has a readable shape.

### COFF Structural Validation

A direct COFF object should be checked in this order:

1. file header;
2. section rows;
3. section data;
4. per-section relocation rows;
5. symbol table;
6. auxiliary symbol rows;
7. string table.

Each section row should be validated according to its storage model.

File-backed sections require a valid raw-data pointer and size.

BSS-style sections require:

```text
logical section size > 0
raw-data pointer = 0
no stored payload bytes
```

Relocation pointers should identify the first relocation row for the section.

The relocation count should match the emitted rows exactly.

Every relocation symbol index must identify the intended symbol-table row,
including auxiliary rows when they affect later indexes.

### COFF Link Validation

The strongest COFF validation is a real link with an independently produced
object.

Use at least one example where the XIRASM object:

- defines a public function;
- owns initialized data;
- owns BSS data;
- references an external function;
- contains a relocation against each relevant section;
- is called from another language.

The consumer should read and write the final byte of the BSS object.

This catches a common false success:

```text
the object links
but the BSS section advertises size zero
```

The consumer should also validate the function result. A successful link alone
does not prove that the relocation addend, calling convention, or stack cleanup
is correct.

### ELF Executable Structural Validation

For a fixed-address ELF executable or PIE, validate:

- ELF class and byte order;
- machine identifier;
- file type;
- entry address;
- program-header offset and count;
- every program-header row;
- load permissions;
- file and memory sizes;
- page congruence.

Every loadable segment should satisfy:

```text
p_offset + p_filesz <= file_size

p_memsz >= p_filesz

p_vaddr % p_align == p_offset % p_align
```

The entry address must lie inside an executable `PT_LOAD`.

No writable `PT_LOAD` should also be executable unless that is an intentional
part of the design.

A BSS-only segment may have `p_filesz = 0` and nonzero `p_memsz`.

The next file-backed segment may reuse the same physical file position while
starting at a later virtual address.

### ELF Object Structural Validation

For an ELF relocatable object, validate:

- `ET_REL` file type;
- absence of program headers;
- section-header offset and count;
- section-name string-table index;
- `SHT_NOBITS` behavior;
- symbol ordering;
- first-global-symbol index;
- symbol-name offsets;
- relocation section links;
- relocation target-section indexes.

Defined symbol values are section-relative in relocatable objects.

Do not interpret them as final virtual addresses.

For REL records, validate the addend stored in the relocated field.

For RELA records, validate the addend stored in the relocation row.

The object should then be linked with an independently produced object that
defines its unresolved symbols.

### ELF Shared-Object Structural Validation

For a shared object, validate both program headers and section headers.

Program headers define what the loader maps.

Section headers describe the file's logical tables and are not a substitute for
load mappings.

Validate:

- `ET_DYN` file type;
- all `PT_LOAD` rows;
- `PT_DYNAMIC`;
- RX and RW separation;
- dynamic symbols;
- dynamic strings;
- hash records;
- PLT relocations;
- GOT slots;
- dynamic tags;
- allocated section addresses.

Every address-valued dynamic tag must contain a runtime virtual address.

String references such as `DT_NEEDED` and `DT_SONAME` contain offsets within
the dynamic string table instead.

Every jump-slot relocation should target the runtime address of its GOT slot.

### ELF Loader Validation

An export-only shared object should be loaded and queried for each public
symbol.

An importing shared object should be loaded with immediate symbol resolution
and should execute a path that crosses:

```text
exported function
-> PLT entry
-> relocated GOT slot
-> imported function
```

Successful execution proves that the loader accepted the load mappings,
processed the dynamic table, resolved the symbol, applied the relocation, and
preserved the required permissions.

A readable relocation table alone cannot prove this.

### Validate Position Independence

PIE and shared-object code must remain valid at different load addresses.

Run the same image repeatedly and observe its loaded address through a value
derived from the program itself.

The exact address does not need to be exposed to users, but multiple runs
should demonstrate that:

- the image can move;
- relative references still reach their targets;
- writable data remains writable;
- imported calls still resolve;
- no field accidentally contains a fixed file offset.

When a format supports both fixed and position-independent modes, validate them
as separate products.

Do not assume that a fixed executable passing validation proves that its PIE
variant is correct.

### ABI Validation

Binary format validation ends at the symbol boundary.

ABI validation begins there.

For every externally callable function, confirm:

- exported name;
- calling convention;
- parameter order;
- parameter width;
- return-value width;
- stack alignment;
- stack ownership;
- preserved registers;
- volatile registers;
- data-layout rules.

An object can contain perfect relocation records and still fail because it
uses the wrong register for the first argument.

A function can return the expected value once and still corrupt its caller by
failing to preserve a nonvolatile register.

Use consumers written independently from the assembly source.

The consumer should not duplicate internal addresses or table constants.

It should interact only through public symbols and the platform ABI.

### Cross-Bitness Validation

PE32 and PE64, or ELF32 and ELF64, are separate layouts.

Do not validate one by scaling the other.

Check the correct:

- machine identifier;
- pointer width;
- optional-header or ELF class;
- symbol record size;
- relocation record size;
- relocation type;
- thunk or GOT entry width;
- calling convention.

A direct helper that accepts `u64` values may still emit a 32-bit field.

The reader must validate the encoded width and reject values that do not fit.

### Validate Permissions as a Security Contract

Permissions are not decoration.

They define what the loader may allow at runtime.

A typical plan separates:

| Content | Permission |
|---|---|
| Headers and read-only data | R |
| Code and PLT | RX |
| Writable data, GOT, and dynamic state | RW |
| BSS | RW |

Avoid writable and executable mappings.

If a format requires temporary loader writes, place the affected slots in a
writable mapping rather than making the code mapping writable.

The validation reader should reject an unexpected W+X section or segment even
when the image executes successfully.

### Validate Compact Physical Output

Virtual page separation should not create unnecessary file-sized zero gaps.

For each range, compare:

```text
next physical start
previous physical start + previous physical size
```

The difference should be explained by an actual alignment requirement or an
emitted record.

Do not infer compactness from the final file size alone.

A small file can still contain overlapping ranges.

A larger file can be correct when the format requires aligned raw data.

The reader should prove:

- physical ranges do not overlap;
- logical ranges do not overlap unintentionally;
- reserve-only tails do not become stored zeros;
- required physical alignment is preserved;
- virtual alignment is represented by addresses, not file padding.

### Validate Finalizer Results

Finalizers patch a stable image.

Validation should confirm both the patched field and the facts used to derive
it.

For example, a section-count field should be checked against the number of
emitted rows, not only against the source constant passed to the header helper.

A table pointer should be checked against the actual first row.

A checksum should be recomputed from final bytes.

A relocation slot should be checked after loading, not only before loading.

This prevents a self-consistent source mistake where the same wrong constant is
used to emit and validate a field.

### Negative Validation

Direct format code should define what must be rejected.

Useful negative cases include:

- row extends beyond the file;
- table count overflows the table range;
- symbol index is out of bounds;
- string offset does not reach a terminator;
- relocation width is zero;
- relocation target cannot fit the encoded field;
- section alignment is invalid;
- load segment violates page congruence;
- memory size is smaller than file size;
- writable and executable permission appears unexpectedly;
- entry point lies outside executable memory;
- dynamic tag uses an FOA where a VA is required.

Negative validation protects the format contract from becoming a collection of
examples that only accept one known-good file.

### Deterministic Output

The same source, inputs, target, and options should produce the same bytes.

Determinism matters for:

- reproducible releases;
- binary comparison;
- cache correctness;
- signature workflows;
- regression analysis.

If an output changes, the changed bytes should be explainable by a source,
input, or tool version change.

Table ordering should not depend on map iteration order, memory addresses, or
filesystem enumeration order.

### A Disciplined Validation Sequence

Use the following sequence for every direct format:

1. Assemble the source.
2. Confirm the final file size.
3. Parse the outer header independently.
4. Validate every table range.
5. Validate every cross-table relationship.
6. Validate coordinate systems.
7. Validate permissions.
8. Link objects with an independent producer.
9. Load executables and shared libraries through the operating system.
10. Call public symbols through the platform ABI.
11. Exercise imports, exports, relocations, BSS, and writable data.
12. Repeat position-independent images at different load addresses.
13. Run negative validation against malformed variants.
14. Confirm deterministic output.

Skipping a layer should be an explicit decision supported by the product's
scope.

### Final Interoperability Checklist

Before publishing a direct format implementation, confirm:

1. The selected file format, class, and machine are correct.
2. All counts match the emitted rows.
3. All table ranges remain inside the file.
4. All additions and multiplications are range-checked.
5. All names terminate inside their string table.
6. All symbol indexes exist.
7. All section indexes exist.
8. All relocation widths are nonzero and supported.
9. All relocation targets use the correct coordinate system.
10. All reserve-only ranges avoid physical zero filling.
11. All physical ranges are compact and non-overlapping.
12. All logical ranges are intentional and non-overlapping.
13. All alignment and congruence rules hold.
14. Entry points lie inside executable mappings.
15. Writable state lies inside writable mappings.
16. Unexpected W+X mappings are rejected.
17. Imports resolve through a native linker or loader.
18. Exports are discoverable by name or ordinal as designed.
19. BSS is allocated and its final byte is usable.
20. Position-independent images work at more than one load address.
21. Checksums and derived header fields match final bytes.
22. Public functions obey the platform ABI.
23. Independent consumers do not depend on internal layout constants.
24. Malformed variants are rejected safely.
25. Repeated builds produce identical bytes.

Direct helpers provide control, not automatic correctness.

The validation strategy is therefore part of the format design and should be
planned alongside the header, section, segment, symbol, and relocation layout.
