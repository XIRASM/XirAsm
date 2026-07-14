# XIRASM Executable Formats Guide

An instruction stream is only one part of an executable file. Operating-system
loaders and native linkers also expect headers, sections or segments,
permissions, symbols, imports, exports, and relocations arranged according to a
specific file format.

XIRASM provides an ordinary format facade for building those files from normal
assembly source:

```asm
import("format/format.inc");
```

This guide teaches that facade through complete PE, COFF, and ELF workflows.
It begins with the common model, then treats each format family separately.
Advanced format-specific helpers are intentionally outside this ordinary
guide and will be documented separately.

Read the [Language Guide](language.md) first when you need the general rules for
values, functions, labels, data emission, output regions, or finalizers. The
[README quick start](../README.md#quick-start) shows how to generate and build
a starter project from the CLI.

## Guide Map

### Part I: Format Fundamentals

1. **Introducing XIRASM Executable Formats**
   - The ordinary facade, a first executable, and the format lifecycle
2. **Format Plans and Lifecycle**
   - Declaring an image, writing named content, binding entries, and finishing
3. **Sections, Segments, Permissions, and BSS**
   - Runtime mappings, file-backed data, reserved memory, and alignment
4. **Addresses, Symbols, and Relocations**
   - VA, RVA, file offsets, imports, exports, and relocation facts

### Part II: Windows Formats

5. **PE32 and PE64 Executables**
   - Console applications, multiple sections, data, BSS, and entry points
6. **Importing Windows APIs**
   - Import declarations, generated tables, and imported calls
7. **DLL Exports and Base Relocations**
   - Exported functions and data, relocation declarations, and ASLR policy
8. **PE Resources and Checksums**
   - Resource data, resource files, and optional image checksums
9. **COFF32 and COFF64 Objects**
   - Sections, public and external symbols, relocations, and native linking

### Part III: ELF Formats

10. **ELF32 and ELF64 Executables**
    - Load segments, compact file layout, data, BSS, and entry points
11. **Position-Independent Executables and Dynamic Imports**
    - PIE images, dynamic metadata, PLT calls, and imported functions
12. **ELF32 and ELF64 Objects**
    - Sections, symbols, REL and RELA relocations, and native linking
13. **ELF64 Shared Objects**
    - Exported symbols, imported symbols, loading, and foreign callers

This guide stops at the ordinary user facade. Direct table construction and
format-specific low-level helpers belong in a separate advanced guide so that
the ordinary workflows remain readable.

## Part I: Format Fundamentals

## 1. Introducing XIRASM Executable Formats

### From Instructions to a Loadable File

Natural ISA text describes what a processor executes:

```asm
x86.use64();

start:
    xor eax, eax
    ret
```

Assembled directly, those instructions form a flat byte sequence. A loader
cannot infer an executable format from the instructions alone. It also needs
answers to questions such as:

- Which bytes contain executable code?
- Which memory ranges are readable or writable?
- Where does execution begin?
- Which data occupies the file, and which storage exists only in memory?
- Which symbols come from other libraries?
- Which addresses must be adjusted when the image is loaded elsewhere?

A standard format records those answers in headers and tables. The format
facade lets source describe the intended image while XIRASM derives the routine
bookkeeping from the completed layout.

### The Ordinary Format Facade

Normal programs begin with one import:

```asm
import("format/format.inc");
```

The ordinary facade provides constructors for:

| Output family | Ordinary constructors |
| --- | --- |
| PE32 and PE64 images | `format_pe32`, `format_pe64` |
| COFF32 and COFF64 objects | `format_coff32`, `format_coff64` |
| ELF32 and ELF64 executables | `format_elf32`, `format_elf64` |
| ELF32 and ELF64 objects | `format_elfobj32`, `format_elfobj64` |
| ELF64 shared objects | `format_elf64_so` |

Constructors create a format plan. The plan records the selected file family,
image options, and the complete list of sections or segments that the source
will write.

The source then follows a common lifecycle:

```text
create the plan
begin the format
write each declared section or segment
attach entry, symbol, import, export, or relocation facts
finish the format
```

The exact declarations differ between an executable, an object file, and a
shared library, but the same principle applies: source supplies semantic facts,
and the facade derives table positions and counts from those facts.

### A First PE64 Executable

The following source creates a 64-bit Windows console executable with one code
section:

```asm
import("format/format.inc");
x86.use64();

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

const image: map = format_entry(image0, start)
format_finish(image);
```

Assemble it with an explicit x86-64 target:

```powershell
xirasm hello.asm --target x86-64 -o hello.exe
.\hello.exe
```

The generated executable returns exit status zero.

ISA instruction lines such as `xor eax, eax` and `ret` do not end with
semicolons. Compile-time calls such as `format_begin(image0);` do.

### Reading the Source as a Lifecycle

The example has six stages.

1. `import("format/format.inc")` selects the ordinary format layer.
2. `x86.use64()` selects the instruction mode used for the code inside the
   image.
3. `format_pe64` creates a PE64 plan with executable, console, NX, and automatic
   ASLR policy options.
4. `format_section` declares one named code section and its permissions.
5. `format_section_begin` and `format_section_end` surround the actual
   instructions that belong to `.text`.
6. `format_entry` binds the entry label, and `format_finish` completes and
   validates the image.

The format choice and ISA choice are related but distinct. `x86.use64()`
controls instruction encoding. `format_pe64(...)` controls the surrounding file
structure.

The descriptor list appears before `format_begin` because it defines the
planned image. Its length determines how many section rows are required, its
order determines their order in the file, and its names connect later content
blocks to those rows.

### What the Source Provides

The ordinary facade keeps user decisions visible:

| Source provides | Example |
| --- | --- |
| File family and image class | PE64 executable |
| Image policy | console, NX, automatic ASLR policy |
| Section or segment names | `.text` |
| Purpose and permissions | code, readable, executable |
| Instructions and data | `xor eax, eax`, `ret` |
| Entry, symbol, import, export, and relocation facts | `start` |

These are decisions that affect program meaning or loader behavior.

### What the Facade Derives

The example does not contain:

- a section count;
- a section-table row index;
- a file offset for `.text`;
- an RVA for `.text`;
- an entry-point field offset;
- a manually calculated header size;
- raw alignment padding.

The facade derives those values from the plan and the completed section layout.
Adding another descriptor changes the required format structure without asking
the user to update a separate count or row number.

Later chapters apply the same rule to generated imports, exports, symbols, and
relocations. Ordinary source names the relevant functions, labels, sections,
segments, permissions, and relocation kinds. The facade assigns indexes,
counts, offsets, and table locations.

### Executables, Objects, and Libraries

This guide covers three broad output roles:

| Role | Loader or consumer | Typical contents |
| --- | --- | --- |
| Executable image | operating-system loader | entry point, runtime mappings, imports |
| Object file | native linker | sections, symbols, external references, relocations |
| Shared library | loader and calling program | exports, imports, runtime metadata |

PE executables and DLLs use sections. COFF objects also use sections but do not
describe a complete runtime image. ELF executables and shared objects use
loadable segments for runtime mappings, while ELF object files use sections for
link-time organization.

The facade uses the vocabulary of the selected format:

```text
format_section_begin(plan, name)
format_section_end(plan, name)

format_segment_begin(plan, name)
format_segment_end(plan, name)
```

Do not substitute one lifecycle for another merely because both contain code
and data.

### Ordinary and Advanced Format Work

Use `format/format.inc` when the ordinary facade can describe the intended
file. It supports the normal multi-section and multi-segment workflows,
including executables, DLLs, objects, shared objects, imports, exports, and
relocations.

Format-specific includes expose narrower or lower-level helpers. They are
useful when implementing a specialized layout or extending the ordinary
facade. Some of those helpers require the caller to manage format invariants
that the ordinary layer normally owns.

Avoid mixing the layers casually. A source should not abandon automatic counts
and layout merely because it needs more than one section, an import table, or a
relocation table.

The separate Format API Reference identifies ordinary and advanced APIs
explicitly. This guide remains focused on complete workflows.

### Starting from the CLI

The CLI can generate starter projects that already use the ordinary facade.
The subcommand comes first, followed by its source override and options:
`xirasm build [source.xir] [options]`. For example, write
`xirasm build --timings`, not `xirasm --timings build`.

Create a PE64 project:

```powershell
xirasm init hello-win --isa x86-64 --os windows --abi msvc
cd hello-win
xirasm build
.\build\app.exe
```

Create an ELF64 project:

```powershell
xirasm init hello-linux --isa x86-64 --os linux --abi sysv
cd hello-linux
xirasm build
```

The generated source follows the same plan, begin, named-content, entry, and
finish lifecycle shown in this chapter.

### Where to Continue

Chapter 2 explains format plans in detail: descriptor order, names, lifecycle
state, entry binding, and generated content. Chapter 3 then separates sections,
segments, file-backed data, BSS, permissions, and alignment.

Keep the first rule simple:

```text
ordinary program -> import("format/format.inc")
specialized format implementation -> choose a lower layer deliberately
```

## 2. Format Plans and Lifecycle

### A Plan Is a Compile-Time Value

An ordinary format constructor returns a `map`:

```text
const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
```

The map is a compile-time description of the intended file. It is not the
finished byte image, and constructing it does not write the section contents.

A plan records the facts needed by its format family:

| Plan family | Primary facts |
| --- | --- |
| PE image | width, image options, sections, entry, and optional generated data |
| COFF object | width, sections, public or external symbols, and relocations |
| ELF executable | width, file mode, load segments, entry, and optional imports |
| ELF object | width, sections, public or external symbols, and relocations |
| ELF shared object | SONAME, load segments, exports, and imports |

Later helper calls may return an updated plan containing additional facts.
Keeping each returned value in a new binding makes the lifecycle visible.

### Descriptors Define the Planned Layout

Sections and segments are declared before `format_begin`:

```text
const sections: list = list.of(
    format_section(
        ".text",
        format_code | format_readable | format_executable
    ),
    format_section(
        ".rdata",
        format_data | format_readable
    )
)
```

Each descriptor contains:

- a name used by later lifecycle calls;
- one content purpose;
- a permission set;
- format-specific attributes derived from those values.

The descriptor list has structural meaning:

| List property | Effect |
| --- | --- |
| Length | determines the number of planned section or segment rows |
| Order | determines row order and runtime mapping order |
| Names | connect later content blocks to their descriptors |
| Purposes | select code, data, BSS, imports, exports, or other behavior |
| Permissions | select readable, writable, executable, or discardable attributes |

Write named content in descriptor order. PE and object tables use descriptor
order for their rows. ELF load segments also use that order when assigning
their logical mappings.

### Plans Are Validated When They Are Created

Constructors reject plans that cannot describe a coherent format.

Common descriptor rules include:

- a section or segment list cannot be empty;
- names cannot be empty or duplicated;
- a descriptor must have exactly one purpose;
- options from mutually exclusive groups cannot be combined;
- special-purpose PE sections such as imports or exports cannot be duplicated;
- segment attributes must be valid for the ordinary ELF layer.

PE and the current COFF facade use section names that fit their eight-byte
section-name fields. ELF object names are stored through `.shstrtab` and may be
longer:

```text
.text
.data
.rodata.long
```

These checks happen before headers or payload are emitted. A malformed plan
therefore fails at its constructor rather than producing a partially valid
file.

### The Five Lifecycle Phases

Ordinary format source follows five phases.

#### 1. Construct the Plan

Choose the format family, options, and complete descriptor list:

```text
const plan0 = format_*(options, descriptors)
```

Object and shared-library constructors may use different arguments, but they
still return a plan.

#### 2. Begin the Format

Start the selected format:

```text
format_begin(plan0);
```

`format_begin` uses the plan kind to emit or reserve the initial structures
needed by that format. Examples include executable headers, program-header
rows, object headers, and fields that can be completed only after layout.

Call it once, after the complete descriptor list exists and before writing
planned content.

#### 3. Write Named Content

Open each declared section or segment, emit its instructions or data, and close
it:

```text
format_section_begin(plan0, ".text");
start:
    xor eax, eax
    ret
format_section_end(plan0, ".text");
```

The name must exist in the plan. The begin call associates the current output
position with the descriptor row. The end call closes the physical extent and
records the final logical and file-backed sizes required by the format.

Use `format_segment_begin` and `format_segment_end` for ELF executable and
shared-object load segments. Use section calls for PE, COFF, and ELF objects.

#### 4. Attach Final Facts

Some facts become available only after their labels or declarations exist.
Executable entry points are the simplest example:

```text
const image: map = format_entry(image0, start)
```

`format_entry` returns a new plan. It does not mutate the binding named
`image0`. Pass the returned value to the next lifecycle operation.

The same value-oriented pattern is used by helpers that attach object symbols,
relocations, executable imports, or shared-object tables:

```text
const plan1 = attach_one_group(plan0, declarations)
const plan2 = attach_another_group(plan1, more_declarations)
format_finish(plan2)
```

The exact helper names belong to the format-specific chapters and the separate
Format API Reference.

#### 5. Finish the Format

Complete the selected file:

```text
format_finish(image);
```

Finishing has format-specific responsibilities:

- PE images finalize the entry and complete plan-owned directory facts;
- ELF executables finalize the entry and optional dynamic metadata;
- COFF and ELF objects emit their symbol, string, and relocation tables;
- ELF shared objects emit their dynamic, symbol, string, export, and import
  metadata.

`format_finish` also rejects missing lifecycle facts. PE images and ELF
executables require a nonzero entry address. Object files and shared objects
finish their tables without inventing an executable entry point.

### A Complete Two-Section Plan

This executable declares two sections before writing either one:

```asm
import("format/format.inc");
x86.use64();

const sections: list = list.of(
    format_section(
        ".text",
        format_code | format_readable | format_executable
    ),
    format_section(
        ".rdata",
        format_data | format_readable
    )
)

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    sections
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
message:
    db("hello", 0);
format_section_end(image0, ".rdata");

const image: map = format_entry(image0, start)
format_finish(image);
```

The plan establishes `.text` as row 0 and `.rdata` as row 1. The later begin
calls use those names instead of caller-supplied row numbers.

Adding a third descriptor requires one new named content block. It does not
require changing a section count, header size, row offset, raw pointer, or RVA.

### Plan Updates Must Be Preserved

This is correct:

```text
const image: map = format_entry(image0, start)
format_finish(image)
```

This finishes the old plan and therefore fails:

```text
const image: map = format_entry(image0, start)
format_finish(image0)
```

The returned `image` contains the entry address. `image0` still contains the
original zero entry.

Use distinct names such as `image0`, `image1`, and `image`, or names that
describe the attached data. The important rule is to pass the newest plan
forward.

### Lifecycle Errors Are Deliberate

The ordinary facade rejects invalid lifecycle operations instead of silently
guessing.

| Mistake | Result |
| --- | --- |
| Empty descriptor list | constructor rejects the plan |
| Duplicate descriptor name | constructor rejects the plan |
| Multiple purposes on one descriptor | descriptor creation fails |
| Unknown section or segment name | begin or related declaration fails |
| Missing executable entry | `format_finish` fails |
| Wrong plan family for a lifecycle call | the call rejects the plan kind |

For example, these two descriptors cannot coexist:

```text
format_section(".text", format_code | format_readable)
format_section(".text", format_data | format_readable)
```

The duplicate name would make later calls such as
`format_section_begin(plan, ".text")` ambiguous, so the plan is rejected before
output begins.

### Generated Content Still Belongs to the Plan

Not every format table is written as a user section or segment. Imports,
exports, dynamic metadata, symbol tables, string tables, and relocation tables
may be generated from declarations attached to the plan.

That generated content still follows the lifecycle:

1. descriptors reserve the user-visible structure;
2. named blocks establish actual layout facts;
3. declaration helpers attach names, labels, and relocation facts;
4. `format_finish` emits or finalizes plan-owned metadata.

This is why imports or relocations should not be added through unrelated manual
table bytes when the ordinary facade already supports them. Manual tables
would bypass the plan that owns counts, indexes, and final locations.

### Practical Plan Rules

Use this checklist when writing an ordinary format source:

1. Declare the complete section or segment list first.
2. Give every descriptor a unique, meaningful name.
3. Give every descriptor exactly one purpose and the required permissions.
4. Call `format_begin` once.
5. Write descriptors in their declared order.
6. Open and close each named content block with the correct lifecycle family.
7. Preserve every updated plan returned by entry or table helpers.
8. Pass the newest plan to `format_finish`.
9. Let the facade derive counts, rows, offsets, sizes, and generated tables.

Chapter 3 explains what the descriptors mean at runtime: sections, load
segments, permissions, file-backed data, BSS, logical size, physical size, and
alignment.

## 3. Sections, Segments, Permissions, and BSS

An executable format describes both stored bytes and the memory image created
from those bytes. Sections, segments, permissions, and BSS are the vocabulary
used to connect those two views.

The ordinary facade keeps the format-specific arithmetic internal. Source code
declares named content and its intended use. The facade derives table rows,
file positions, virtual addresses, sizes, and alignment.

### Sections and Segments Answer Different Questions

A **section** describes a named part of a file. A **segment** describes a range
that an ELF loader maps into memory.

The ordinary layer uses them as follows:

| Format family | Descriptor | Primary role |
| --- | --- | --- |
| PE executable or DLL | section | file content and image mapping |
| COFF object | section | linker input, symbols, and relocations |
| ELF object | section | linker input and section metadata |
| ELF executable or PIE | segment | runtime `LOAD` mapping |
| ELF shared object | segment | runtime `LOAD` mapping |

PE sections carry both file-layout and memory-permission information. ELF
programs instead place runtime content in loadable segments. ELF object files
still use sections because they are linker inputs rather than complete runtime
images.

This distinction changes the descriptor constructor:

```text
format_section(name, purpose | permissions)
format_segment(name, format_load | permissions)
```

Do not pass a section purpose such as `format_data` to `format_segment`.
Ordinary ELF program segments use `format_load`; their permissions and actual
contents distinguish code, read-only data, writable data, and BSS.

### Every Section Has One Purpose

A section descriptor contains exactly one purpose. The ordinary facade defines
these section purposes:

| Purpose | Intended content |
| --- | --- |
| `format_code` | instructions and executable data |
| `format_data` | initialized data |
| `format_uninitialized_data` | BSS-style storage |
| `format_imports` | generated PE import data |
| `format_exports` | generated PE export data |
| `format_resources` | PE resources |
| `format_fixups` | PE base relocations |

The first three purposes are used by PE, COFF, and ELF object plans. The
remaining purposes describe generated PE sections and are covered in the
Windows-format chapters.

Combining two purposes is invalid:

```text
format_section(
    ".bad",
    format_code | format_data | format_readable
)
```

The facade cannot derive coherent section characteristics from that
descriptor, so it rejects the plan before output begins.

### Permissions Describe the Loaded Memory

Permissions are independent flags combined with a purpose:

| Permission | Meaning |
| --- | --- |
| `format_readable` | the mapped range may be read |
| `format_writeable` | the mapped range may be written |
| `format_executable` | instructions may execute from the range |
| `format_discardable` | PE may discard the section after use |

`format_discardable` belongs to ordinary PE section plans. COFF objects and ELF
objects reject it, and ELF program segments do not accept it.

Common combinations are:

```text
format_code | format_readable | format_executable
format_data | format_readable
format_data | format_readable | format_writeable
format_uninitialized_data | format_readable | format_writeable
format_load | format_readable | format_executable
format_load | format_readable | format_writeable
```

The assembler does not prevent a writable and executable mapping, but most
programs should keep code and mutable data separate. A clear default is:

- code: readable and executable;
- constants: readable;
- mutable initialized data: readable and writeable;
- BSS: readable and writeable.

Permissions describe the generated format. They do not restrict what the
assembler can read or write while constructing the file.

### Named Content Must Match the Descriptor Kind

Sections use the section lifecycle:

```text
format_section_begin(plan, ".text")
    ...
format_section_end(plan, ".text")
```

Segments use the segment lifecycle:

```text
format_segment_begin(plan, ".text")
    ...
format_segment_end(plan, ".text")
```

The name resolves a descriptor already stored in the plan. It is not a new
declaration. The begin call establishes the logical and physical start of the
content; the end call closes the extent so the facade can finalize its sizes.

Use the matching lifecycle family:

- PE, COFF, and ELF object plans use section calls;
- ELF executable, PIE, and shared-object plans use segment calls.

Passing a segment plan to `format_section_begin`, or a section plan to
`format_segment_begin`, is an error rather than an implicit conversion.

### File-Backed Bytes and Memory-Only Storage

Instructions and data emit real file bytes. Reserved storage advances logical
size without necessarily adding bytes to the final file.

When reserved storage remains at the end of a section or segment, the ordinary
facade can represent it as memory-only storage:

```text
bss_start:
    rb(64)
```

This is the central BSS relationship:

```text
logical size > file-backed size
```

For a pure 64-byte BSS range:

```text
file-backed size = 0
logical size     = 64
```

For an ELF load segment containing four initialized bytes followed by 64
reserved bytes:

```text
file-backed size = 4
logical size     = 68
```

The loader obtains the initialized prefix from the file and supplies zeroed
memory for the remaining range.

Reserved storage must remain at the tail to stay file-free. If more bytes are
emitted after a reserved gap in the same output area, that gap becomes part of
the file-backed layout. Use a separate BSS descriptor when the storage should
remain entirely absent from the file.

The underlying logical and physical coordinate model is introduced in
[Output Regions and Virtual Data](language.md#11-output-regions-and-virtual-data).
Ordinary format sources normally do not call region APIs directly.

### BSS in Sections and Segments

BSS is expressed differently across format families.

For PE, COFF, and ELF objects, declare an uninitialized-data section:

```text
format_section(
    ".bss",
    format_uninitialized_data
        | format_readable
        | format_writeable
)
```

The resulting meaning is format-specific:

- PE records a virtual section size with no raw section bytes;
- COFF marks the section as uninitialized data;
- ELF objects use a no-file-data section type.

For ELF executables, PIEs, and shared objects, declare a writable load segment
and emit only reserved storage:

```text
format_segment(
    ".bss",
    format_load | format_readable | format_writeable
)
```

The program header then records a zero file size and a nonzero memory size.
There is no separate `format_bss` segment purpose.

### A PE64 Image with Four Section Roles

This example separates code, constants, mutable data, and BSS:

```asm
import("format/format.inc");
x86.use64();

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".rdata",
            format_data | format_readable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data
                | format_readable
                | format_writeable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
message:
    db("ready", 0);
format_section_end(image0, ".rdata");

format_section_begin(image0, ".data");
counter:
    dq(1);
format_section_end(image0, ".data");

format_section_begin(image0, ".bss");
workspace:
    rb(64);
format_section_end(image0, ".bss");

const image: map = format_entry(image0, start)
format_finish(image);
```

The section table records four rows in declaration order. `.text`, `.rdata`,
and `.data` occupy file space. `.bss` has a logical size of 64 bytes and a raw
size of zero.

PE file alignment and image alignment are different. File-backed section data
uses the PE file alignment, while section virtual addresses advance using the
PE section alignment. The ordinary facade applies both rules.

### An ELF64 Image with BSS Between File-Backed Segments

The next example deliberately places a pure BSS segment before a final
read-only segment:

```asm
import("format/format.inc");
x86.use64();

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        ),
        format_segment(
            ".data",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".bss",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".rodata",
            format_load | format_readable
        )
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
start:
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image0, ".text");

format_segment_begin(image0, ".data");
counter:
    dq(1);
format_segment_end(image0, ".data");

format_segment_begin(image0, ".bss");
workspace:
    rb(128);
format_segment_end(image0, ".bss");

format_segment_begin(image0, ".rodata");
message:
    db("ready", 0);
format_segment_end(image0, ".rodata");

const image: map = format_entry(image0, start)
format_finish(image);
```

The BSS segment contributes 128 bytes to memory and zero bytes to the file.
The following `.rodata` segment may therefore begin at the same file offset
where the BSS segment begins. Its virtual address still advances beyond the BSS
memory range.

ELF load alignment does not require a page-sized hole in the file. The facade
keeps file offsets compact while choosing virtual addresses that satisfy:

```text
virtual address modulo alignment = file offset modulo alignment
```

This preserves loader alignment without writing unused page padding.

### Alignment Is Derived by the Facade

Ordinary sources should not manually align section-table rows, program-header
rows, raw pointers, RVAs, or load addresses.

The facade applies the relevant format rules:

- PE separates file alignment from section virtual alignment;
- COFF and ELF objects select section alignment from purpose and width;
- ELF load segments retain their required page alignment;
- file-free BSS advances logical memory without creating a page-sized file
  hole;
- later file-backed content continues from the committed real file position.

Explicit region alignment belongs to advanced custom-layout work. Mixing it
into an ordinary plan can duplicate or contradict the format layer's layout
policy.

### Invalid Attribute Combinations Fail Early

Descriptors reject attributes that have no meaning for their kind:

```text
format_section(
    ".text",
    format_code | format_load | format_readable
)
```

`format_load` is a segment purpose, so this section declaration is invalid.

Likewise:

- section descriptors reject unknown flags;
- segment descriptors reject section-purpose flags;
- ELF object sections reject PE-only discardable behavior;
- COFF object sections accept code, data, and uninitialized data only;
- every descriptor requires exactly one purpose;
- names must be unique within one plan.

These failures prevent a source from silently requesting an attribute that the
generated format would ignore.

### Practical Layout Rules

Use these defaults when planning ordinary content:

1. Use one descriptor for each distinct permission or storage role.
2. Keep code readable and executable, but not writeable.
3. Keep constants readable and not writeable.
4. Keep mutable data and BSS readable and writeable.
5. Use `format_uninitialized_data` for PE, COFF, and ELF object BSS.
6. Use a reserve-only writable `format_load` segment for ELF runtime BSS.
7. Keep reserved file-free storage at the end of its section or segment.
8. Write descriptors in plan order and close every opened content block.
9. Let the facade derive counts, addresses, offsets, sizes, and alignment.

Chapter 4 builds on these layout rules by explaining addresses, symbols,
fixups, and relocations.

## 4. Addresses, Symbols, and Relocations

A label gives source code a stable name for a logical address. Executable and
object formats then translate that address into the coordinate required by a
header, symbol table, relocation record, instruction field, or loader.

The important rule is to preserve the coordinate's meaning. A virtual address,
relative virtual address, section offset, and file offset may describe the
same byte from different viewpoints, but they are not interchangeable values.

### Name the Coordinate You Mean

The ordinary format layer works with several address forms:

| Coordinate | Meaning |
| --- | --- |
| logical address | the label value in the active output region |
| virtual address | the address used when the image is mapped |
| RVA | a PE virtual address relative to the image base |
| section offset | a position relative to an object-file section |
| file offset | a physical byte position in the generated file |

For example, a PE entry label has a logical address. The PE header stores its
RVA. An object symbol stores a value relative to its section. A section header
stores a file offset for the section's bytes.

Ordinary source should pass labels and section-start labels to the facade. It
should not calculate these derived values manually:

```text
format_entry(image0, start)
format_coff_public("caller", ".text", text_start, caller, ...)
format_coff_reloc(".text", text_start, patch_field, "callee", ...)
```

The facade derives the entry RVA, symbol value, relocation offset, table index,
and file position required by the selected format.

Do not use a file offset as a pointer. File offsets identify stored bytes.
Virtual and logical addresses identify mapped memory.

### Internal ISA References Use Assembler Fixups

References to labels inside instructions normally require no explicit format
relocation:

```text
start:
    jmp finished
    nop

finished:
    ret
```

The assembler records the symbolic operand, determines the final instruction
layout, and patches the encoded displacement. This is an **ISA fixup**.

The fixup resolves entirely while assembling the file when the target is known
and the selected format does not need another program to adjust it.

Use labels directly in instruction operands whenever possible. Do not replace
them with manually calculated displacements.

### An Entry Point Is a Final Image Address

PE executables and DLLs, plus ELF executables and PIEs, require an entry
address:

```text
const image: map = format_entry(image0, start)
format_finish(image)
```

`format_entry` stores the logical label address in a new plan. The format
finalizer writes the representation required by the image:

- PE stores an RVA relative to the image base;
- ELF stores the executable virtual address.

The entry must be attached after the label exists, and the updated plan must be
passed to `format_finish`.

Object files and ELF shared objects do not use this lifecycle call. Objects
publish symbols for a linker. Shared objects publish exports and dynamic
metadata. Passing either kind of plan to `format_entry` is an error.

### Fixups and Relocations Are Different Operations

The word *relocation* is used for several related mechanisms. Keep their owners
separate:

| Mechanism | Owner | Purpose |
| --- | --- | --- |
| ISA fixup | assembler | resolve a known symbolic instruction field |
| object relocation | linker | resolve or move a symbol during final linking |
| PE base relocation | loader | adjust absolute image addresses after rebasing |
| dynamic relocation | dynamic loader | resolve runtime imports or movable data |

An internal branch may need only an ISA fixup. A call to an external object
symbol needs an object relocation. An absolute pointer inside a relocatable PE
image needs a PE base relocation even when its target is defined in the same
source.

Dynamic ELF imports and position-independent data are covered in the ELF
chapters. This chapter establishes the shared address model.

### Stable Absolute Values Must Be Written after Layout

An instruction operand may remain symbolic until fixup resolution. An ordinary
integer expression does not automatically retain that symbolic relationship.

For an absolute pointer stored in data, reserve the field and write the final
address in `defer`:

```text
entry_pointer:
    dq(0)

defer {
    store.u64(entry_pointer, start);
}
```

The finalizer runs after instruction sizes, regions, labels, and layout are
stable. It writes the real logical address rather than an early temporary
value.

This backfill solves the value of the field. It does not by itself tell an
operating-system loader to change that field when the image is loaded at a
different base. PE images need a base relocation for that second operation.

### PE Base Relocations Identify Absolute Slots

A PE base relocation describes the address of a field that contains an
absolute virtual address tied to the preferred image base. The loader adds the
image-base delta to that field when the image is rebased.

The ordinary facade separates the steps:

1. emit an absolute slot;
2. add the slot address to a relocation list;
3. emit the generated relocation section;
4. backfill the final absolute pointer value.

`format_pe_reloc_add` selects the relocation width from the PE plan:

- PE32 uses a 32-bit high-low relocation;
- PE64 uses a 64-bit relocation.

The caller supplies the slot's logical address. The facade derives its RVA,
groups relocation entries by page, sorts them, and emits the directory.

### A PE64 Executable with a Relocatable Pointer

This image requires ASLR support and contains one absolute pointer:

```asm
import("format/format.inc");
x86.use64();

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_required,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".reloc",
            format_fixups | format_readable | format_discardable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret

entry_pointer:
    dq(0);
format_section_end(image0, ".text");

const relocs0: list = pe_reloc_new()
const relocs: list = format_pe_reloc_add(
    image0,
    relocs0,
    entry_pointer
)
format_pe_reloc_section(image0, ".reloc", relocs);

const image: map = format_entry(image0, start)
format_finish(image);

defer {
    store.u64(entry_pointer, start);
}
```

The pointer field is initialized with the final address of `start`. The
relocation directory identifies `entry_pointer` as the field that must move
when the loader changes the image base.

`format_pe_aslr_required` makes the relocation requirement explicit. An image
using that policy fails rather than silently claiming relocatability without a
relocation directory.

### Object Symbols Describe Linker-Visible Names

An object file is not assigned its final runtime addresses. It records symbols
and relocations so a linker can place sections and resolve references later.

The ordinary object facade uses two symbol categories:

- a **public symbol** is defined by this object;
- an **external symbol** is required from another object or library.

A public symbol declaration receives:

```text
name
section name
section start label
symbol address
symbol type
```

The ELF object form also records symbol size. The facade derives the
section-relative symbol value:

```text
symbol value = symbol address - section start
```

An external symbol has no local section or address. Its name becomes the
relocation target.

### Object Relocations Identify Patch Fields

An object relocation connects four facts:

```text
section containing the field
offset of the field within that section
target symbol name
relocation type
```

The source passes the section start and patch-field label. The facade derives
the section-relative relocation offset:

```text
relocation offset = patch field address - section start
```

Symbol indexes are assigned from the symbol declaration list. The caller does
not calculate them.

COFF relocation addends are represented in the bytes at the patch field. ELF
relocation forms may carry an explicit addend. The object-format chapters
explain the relocation types and addend conventions for each width.

### A COFF64 Object with an External Call

An external symbol is not a local label, so the call field is emitted as a
placeholder and associated with a relocation:

```asm
import("format/format.inc");
x86.use64();

const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
format_begin(object0);

format_section_begin(object0, ".text");
text_start:
caller:
    db(0xe8);
call_displacement:
    dd(0);
    ret
format_section_end(object0, ".text");

const symbols: list = list.of(
    format_coff_public(
        "caller",
        ".text",
        text_start,
        caller,
        coff_sym_type_function
    ),
    format_coff_extern(
        "callee",
        coff_sym_type_function
    )
)
const relocs: list = list.of(
    format_coff_reloc(
        ".text",
        text_start,
        call_displacement,
        "callee",
        coff_rel_amd64_rel32
    )
)
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);
```

The object contains:

- one public `caller` symbol in `.text`;
- one undefined external `callee` symbol;
- one relative relocation at `call_displacement`;
- a relocation target resolved by symbol name.

The symbol table and relocation table are emitted during `format_finish`.
Their indexes, file offsets, and row counts come from the plan.

### ELF Object Declarations Follow the Same Model

ELF object declarations use the same source-level relationships:

```text
format_elfobj_public(
    name,
    section_name,
    section_start,
    address,
    size,
    symbol_type
)

format_elfobj_extern(name, symbol_type)

format_elfobj_reloc(
    section_name,
    section_start,
    patch_address,
    symbol_name,
    relocation_type,
    addend
)
```

The facade creates the symbol table, string tables, relocation sections, and
section-header links required by the ELF object. The caller supplies names,
labels, symbol meaning, relocation type, and addend.

The detailed ELF32 and ELF64 relocation forms are deferred to the ELF object
chapter so this chapter can keep one coordinate model.

### Relocation Declarations Are Validated

Object table construction rejects inconsistent declarations:

- public symbols must name a declared section;
- symbol names must be unique within the user symbol list;
- relocation fields cannot precede their section start;
- relocation sections must exist in the plan;
- every relocation target name must match a declared symbol;

PE relocation sections also require at least one relocation and must use a
section declared with the `format_fixups` purpose.

These checks keep invalid symbol indexes or unrelated section coordinates out
of the generated file.

### Do Not Confuse a Pointer with Its Relocation

The stored value and its relocation record solve different problems:

```text
stored pointer     = the address currently written in the field
relocation record  = instructions for changing that field later
```

A zero placeholder plus a relocation record is sufficient in an object file
because the linker owns the final value. A completed PE image also needs the
current absolute value in the field before the loader can apply a base delta.

Likewise, a relocation record is unnecessary for a fully resolved relative
branch whose displacement is fixed during assembly.

### Practical Address and Relocation Rules

1. Use labels for logical addresses and instruction targets.
2. Let ISA fixups resolve internal symbolic instruction fields.
3. Use `format_entry` only with PE or ELF executable plans.
4. Pass the updated entry plan to `format_finish`.
5. Keep file offsets separate from virtual addresses and RVAs.
6. Use a finalizer when a raw absolute data field needs the stable address.
7. Add a PE base relocation for every absolute slot that must follow rebasing.
8. Declare object public and external symbols by name.
9. Declare object relocations from a section start and patch-field label.
10. Let the facade assign symbol indexes, relocation rows, and file positions.

Part II now applies these fundamentals to Windows formats, beginning with PE32
and PE64 executable construction.

## Part II: Windows Formats

## 5. PE32 and PE64 Executables

Portable Executable images divide a Windows program into named sections and
describe how each section is stored in the file and mapped into memory. The
ordinary facade builds the DOS header, PE signature, file header, optional
header, data directories, and section table from one declared plan.

This chapter builds normal executable images. Imports, DLL exports, resources,
checksums, and complete base-relocation workflows are covered in later
chapters.

### Choose the Width before Writing Content

Use `format_pe32` for a 32-bit x86 image and `format_pe64` for a 64-bit x86
image:

```text
format_pe32(options, sections)
format_pe64(options, sections)
```

Both constructors use the same section descriptors and lifecycle. The width
changes the machine type, optional-header form, default image base, pointer
width, and relocation type used by absolute address fields.

`format_begin` selects the corresponding x86 instruction mode. An explicit
`x86.use32()` or `x86.use64()` near the top of the source is still useful
because it states the intended ISA width before the first instruction appears.
The command-line target should agree with that intent.

| Image | Constructor | Command-line target | Default image base |
| --- | --- | --- | --- |
| 32-bit x86 | `format_pe32` | `x86` or `x86-32` | `0x00400000` |
| 64-bit x86 | `format_pe64` | `x86-64` | `0x0000000140000000` |

The default file alignment is 512 bytes. The default section alignment in
memory is 4096 bytes. Ordinary sources declare section roles and permissions;
they do not calculate aligned RVAs or raw file positions.

### Select the Image Role, Subsystem, and Safety Policy

The PE constructor receives one option value assembled from independent
choices:

```text
image role       format_pe_exe
subsystem        format_pe_console or format_pe_gui
memory policy    format_pe_nx
ASLR policy      format_pe_aslr_auto
                 format_pe_aslr_required
                 format_pe_aslr_disabled
```

An executable plan must select exactly one image role, one subsystem, and one
ASLR policy. Unknown or contradictory options are rejected before output
begins.

For ordinary executables, a useful default is:

```text
format_pe_exe
    | format_pe_console
    | format_pe_nx
    | format_pe_aslr_auto
```

`format_pe_nx` marks the image as compatible with non-executable data memory.
Section permissions still decide which individual sections may execute.

The subsystem describes the program's Windows environment:

- `format_pe_console` selects the console subsystem;
- `format_pe_gui` selects the graphical subsystem.

The subsystem does not generate a runtime library, create a window, or add
imports. It only records the loader-visible subsystem choice. A graphical
program still needs the imports and startup behavior required by its own code.

### A PE64 Console Executable

The following image separates code, read-only data, mutable data, and reserved
storage:

```asm
import("format/format.inc");
x86.use64();

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".rdata",
            format_data | format_readable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data
                | format_readable
                | format_writeable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
message:
    db("XIRASM PE64", 0);
format_section_end(image0, ".rdata");

format_section_begin(image0, ".data");
counter:
    dd(1);
format_section_end(image0, ".data");

format_section_begin(image0, ".bss");
workspace:
    rb(128);
format_section_end(image0, ".bss");

const image: map = format_entry(image0, start)
format_finish(image);
```

Assemble the source for x86-64:

```powershell
xirasm program.asm --target x86-64 -o program.exe
.\program.exe
```

The minimal entry returns zero. Chapter 6 replaces this minimal return path
with an explicit call to an imported Windows API.

### Read the Plan by Section Role

The section list is the image layout contract:

| Section | Purpose | Permissions | File content |
| --- | --- | --- | --- |
| `.text` | code | read, execute | instructions |
| `.rdata` | initialized data | read | constant bytes |
| `.data` | initialized data | read, write | mutable initial values |
| `.bss` | uninitialized data | read, write | no raw payload |

The facade emits one section-table row for each descriptor in the same order.
The later `format_section_begin` and `format_section_end` calls fill those
named rows.

`.bss` advances the logical image size by 128 bytes but does not add 128 zero
bytes to the file. Its section row records memory size with a zero raw size.
The next file-backed section, if any, may reuse the same physical file cursor
while receiving a later aligned RVA.

The labels `message`, `counter`, and `workspace` are ordinary logical
addresses. They are available to later instructions, finalizers, exports, or
relocation declarations even though their sections have different file and
memory coordinates.

### Bind the Entry after Defining It

The entry label must exist before the final plan is created:

```text
const image: map = format_entry(image0, start)
format_finish(image)
```

`format_entry` returns an updated plan. Passing `image0` to `format_finish`
would discard the entry binding and fail because an executable image requires
an entry point.

The PE header stores the entry as an RVA. Source passes the logical label;
the facade derives the RVA from the selected image base and final section
layout.

### A PE32 Executable Uses the Same Workflow

The 32-bit form changes the constructor, ISA width, and command-line target.
The plan and section lifecycle remain the same:

```asm
import("format/format.inc");
x86.use32();

const image0: map = format_pe32(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data
                | format_readable
                | format_writeable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

format_section_begin(image0, ".data");
counter:
    dd(1);
format_section_end(image0, ".data");

format_section_begin(image0, ".bss");
workspace:
    rb(64);
format_section_end(image0, ".bss");

const image: map = format_entry(image0, start)
format_finish(image);
```

Assemble it with a 32-bit x86 target:

```powershell
xirasm program32.asm --target x86 -o program32.exe
.\program32.exe
```

The PE32 image uses the 32-bit optional header and the i386 machine type. The
PE64 image uses the PE32+ optional header and the AMD64 machine type.

### Width Changes Address Fields, Not the Plan Model

The most important differences appear when source stores or relocates absolute
addresses:

| Concern | PE32 | PE64 |
| --- | --- | --- |
| Absolute pointer field | 32 bits | 64 bits |
| Typical data declaration | `dd(0)` | `dq(0)` |
| Final backfill | `store.u32` | `store.u64` |
| Base relocation | HIGHLOW | DIR64 |
| Default image base | `0x00400000` | `0x0000000140000000` |
| Large-address-aware flag | not used by the facade | enabled |
| High-entropy ASLR flag | not applicable | enabled with relocatable ASLR |

These differences do not require separate section-management code. The same
ordinary descriptors, named section calls, entry binding, and finish operation
work at both widths.

Do not place a 64-bit address in a PE32 data field or use a PE32 relocation
kind for a PE64 pointer. Chapter 7 shows complete relocatable pointer and DLL
workflows.

### Understand the Three ASLR Policies

The ordinary facade keeps the image flags consistent with the relocation data
that the source actually provides.

#### Automatic

`format_pe_aslr_auto` enables the dynamic-base flag only when the plan contains
a real `format_fixups` section. Without fixups, the image remains a valid
fixed-base executable instead of claiming that the loader may safely rebase
it.

This makes `auto` a useful ordinary default:

```text
no fixups section     fixed-base image
fixups section        relocatable image
PE64 with fixups      dynamic base and high-entropy VA
```

#### Required

`format_pe_aslr_required` rejects a plan without a `format_fixups` section.
Use it when being relocatable is part of the program's contract.

#### Disabled

`format_pe_aslr_disabled` leaves the dynamic-base flag clear. It is appropriate
when the image is intentionally tied to its preferred base.

An ASLR option does not discover absolute pointers automatically. Source must
still declare every field that needs a base relocation.

### File Alignment and Memory Alignment Are Separate

PE sections have two coordinate systems:

- raw file data is aligned to the file alignment;
- loaded section RVAs are aligned to the section alignment.

The ordinary facade uses 512-byte file alignment and 4096-byte section
alignment. A small executable can therefore have compact file-backed sections
while each loaded section begins at a page-aligned RVA.

BSS demonstrates why these coordinates must remain separate. A BSS section can
occupy memory without occupying raw file bytes. The facade computes raw sizes,
virtual sizes, raw pointers, RVAs, `SizeOfHeaders`, and `SizeOfImage` from the
final section facts.

Ordinary source should not insert manual file padding to imitate PE section
alignment.

### Common PE Executable Mistakes

#### Contradictory Options

A PE plan fails when it selects both EXE and DLL, both console and GUI, or more
than one ASLR policy.

#### Missing or Discarded Entry

An executable must bind an entry label, and the updated plan returned by
`format_entry` must reach `format_finish`.

#### Undeclared Section Names

Every `format_section_begin` call must name one descriptor from the original
plan. A section cannot be opened twice, and the final image must complete all
declared section content.

#### Incorrect Permissions

Code normally needs read and execute permissions, not write permission.
Mutable data and BSS normally need read and write permissions, not execute
permission.

#### Claiming Relocatability without Fixups

Use `format_pe_aslr_auto` when relocatability is optional. Use
`format_pe_aslr_required` only when the plan includes the relocation section
and every required absolute field has a relocation declaration.

### Practical PE Executable Rules

1. Use `format_pe64` for normal 64-bit Windows programs.
2. Use `format_pe32` only when the program must run as 32-bit x86 code.
3. Select exactly one subsystem and one ASLR policy.
4. Enable `format_pe_nx` for ordinary applications.
5. Declare the complete section list before `format_begin`.
6. Separate code, constants, mutable data, and BSS by purpose and permission.
7. Bind the entry label through the returned plan from `format_entry`.
8. Let the facade derive section rows, RVAs, raw pointers, and image sizes.
9. Use `format_pe_aslr_auto` unless the image requires a stricter policy.
10. Add imports, relocations, resources, and checksums through their dedicated
    workflows rather than manual header edits.

Chapter 6 extends the executable plan with generated import tables and a real
call to a Windows API.

## 6. Importing Windows APIs

A PE executable does not contain the implementation of every function it
calls. An import table names the required DLLs and procedures, and the Windows
loader writes their resolved addresses into the image's import address table.

The ordinary facade lets source describe imports by name. It generates the
descriptors, lookup tables, hint/name records, DLL names, address-table slots,
terminators, and PE import-directory entry.

### Imports Are an Immutable Compile-Time Value

Begin with an empty import set:

```text
const imports0: map = pe_import_new()
```

Add each required procedure by returning a new map:

```text
const imports1: map = pe_import_use64(
    imports0,
    "KERNEL32.DLL",
    "ExitProcess"
)
```

Use the function that matches the image width:

| Image | Named import | Named import with local slot name |
| --- | --- | --- |
| PE32 | `pe_import_use32` | `pe_import_use32_as` |
| PE64 | `pe_import_use64` | `pe_import_use64_as` |

The non-`as` form uses the imported procedure name as the local IAT label. The
`as` form separates the external procedure name from the label used by
assembly source:

```text
pe_import_use64_as(
    imports,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)
```

This records:

```text
DLL name              KERNEL32.DLL
imported procedure    ExitProcess
local IAT label       exit_process
```

The label denotes the address-table slot, not the procedure body. After the
image is loaded, the slot contains the resolved procedure address.

### Declare an Import Section in the Image Plan

The plan must contain one section with the `format_imports` purpose:

```text
format_section(
    ".idata",
    format_imports | format_readable | format_writeable
)
```

The section is writable because the loader fills its address-table slots. It
does not need execute permission.

Emit the complete import set with:

```text
format_pe_import_section(image, ".idata", imports)
```

This operation opens and closes the named section itself. Do not surround it
with a separate `format_section_begin` and `format_section_end` pair.

### A PE64 Executable That Calls an Imported API

This executable imports `ExitProcess`, gives its IAT slot a lowercase local
name, and calls it through a RIP-relative memory operand:

```asm
import("format/format.inc");
x86.use64();

const imports0: map = pe_import_new()
const imports: map = pe_import_use64_as(
    imports0,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".idata",
            format_imports | format_readable | format_writeable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    sub rsp, 40
    xor ecx, ecx
    call [rel exit_process]
format_section_end(image0, ".text");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);
```

Assemble and run it as a 64-bit Windows executable:

```powershell
xirasm imported-exit.asm --target x86-64 -o imported-exit.exe
.\imported-exit.exe
```

The program passes zero to `ExitProcess` and terminates with exit status zero.

### Follow the Windows x64 Calling Convention

The first four integer or pointer arguments use:

```text
argument 0    rcx
argument 1    rdx
argument 2    r8
argument 3    r9
```

The caller must also provide 32 bytes of shadow space and maintain 16-byte
stack alignment at the call boundary. The example uses:

```text
sub rsp, 40
xor ecx, ecx
call [rel exit_process]
```

The 40-byte adjustment combines the 32-byte shadow space with the alignment
adjustment required at a normal function entry. `ExitProcess` does not return.
For an imported function that does return, restore the stack before leaving
the current routine:

```text
sub rsp, 40
set argument registers
call [rel imported_slot]
add rsp, 40
```

Registers that are volatile under the Windows x64 calling convention must be
treated as changed after the call. Code that uses nonvolatile registers must
preserve and restore them.

The `rel` operand is important. It encodes the address of the IAT slot relative
to the next instruction rather than embedding the image's absolute base
address in the call field.

### A PE32 Imported Call

The PE32 form uses a 32-bit IAT slot and places this API argument on the stack:

```asm
import("format/format.inc");
x86.use32();

const imports0: map = pe_import_new()
const imports: map = pe_import_use32_as(
    imports0,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)

const image0: map = format_pe32(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_disabled,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".idata",
            format_imports | format_readable | format_writeable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    push 0
    call [exit_process]
format_section_end(image0, ".text");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);
```

The 32-bit indirect memory operand contains the absolute address of the IAT
slot. This minimal example therefore selects `format_pe_aslr_disabled`.
Chapter 7 shows how absolute PE32 fields participate in base relocation.

Do not apply the Windows x64 register and shadow-space rules to PE32 calls.
The exact 32-bit calling convention and argument cleanup belong to the
imported procedure's contract. This example uses the documented stack argument
shape of `ExitProcess`.

### The Loader Replaces IAT Contents

Before loading, each address-table slot contains import metadata. The import
directory tells the loader which DLL and procedure belong to that slot.

During image loading, Windows:

1. loads or locates each named DLL;
2. resolves each imported procedure;
3. writes the resolved address into the corresponding IAT slot;
4. transfers control to the executable entry point.

The call instruction reads the resolved address from the slot:

```text
source label        exit_process
label location      one IAT slot inside .idata
loaded slot value   address of ExitProcess
call target         loaded slot value
```

Source does not calculate the import descriptor RVA, lookup-table RVA,
address-table RVA, or hint/name offsets.

### Add More Than One Import

Build the import set step by step and preserve the latest returned map:

```text
const imports0: map = pe_import_new()
const imports1: map = pe_import_use64_as(
    imports0,
    "KERNEL32.DLL",
    "GetStdHandle",
    "get_std_handle"
)
const imports2: map = pe_import_use64_as(
    imports1,
    "KERNEL32.DLL",
    "WriteFile",
    "write_file"
)
const imports: map = pe_import_use64_as(
    imports2,
    "KERNEL32.DLL",
    "ExitProcess",
    "exit_process"
)
```

Imports from the same DLL share one descriptor. Imports from another DLL are
placed under another key in the import map and receive another descriptor.

Adding the same local slot with the same DLL and imported name is idempotent.
Reusing a slot name for a different import is rejected.

The facade derives a deterministic table order from the completed import
value. Calls should depend on slot labels, not on table positions.

### Named Imports and Ordinal Imports

Named imports are the normal choice because they make source and diagnostics
readable. The format layer also provides width-specific ordinal forms:

```text
pe_import_use32_ordinal_as(imports, dll, ordinal, slot)
pe_import_use64_ordinal_as(imports, dll, ordinal, slot)
```

An ordinal must fit in 16 bits. Use ordinal imports only when the target DLL's
binary interface specifies an ordinal as its stable contract. The local slot
label is still used at the call site.

### Keep Import Metadata out of the Code Section

The import section contains writable loader metadata and should not be
executable. The code section should contain instructions and ordinary
instruction fixups, not hand-written import descriptors or thunk arrays.

A clear plan keeps the responsibilities separate:

```text
.text     read + execute     call sites
.rdata    read               constants used by API calls
.data     read + write       mutable arguments and results
.idata    read + write       generated import metadata and IAT slots
```

Additional data sections are optional. Declare only the sections that the
program actually uses.

### Common Import Mistakes

#### Forgetting the Import Section

`format_pe_import_section` requires a declared section whose purpose is
`format_imports`.

#### Opening `.idata` Manually

The ordinary helper manages the import section lifecycle. Opening the same
section manually causes a duplicate or mismatched section operation.

#### Discarding an Updated Import Map

Every `pe_import_use*` call returns a new map. Passing an earlier map to
`format_pe_import_section` omits later imports.

#### Calling the Slot Address Instead of Its Contents

The import label identifies a pointer slot. Use an indirect memory call such
as `call [rel exit_process]` or `call [exit_process]`, not a direct call to the
slot's address.

#### Mixing Widths

Use 32-bit import declarations with PE32 and 64-bit declarations with PE64.
The address-table entry width and ordinal flag differ.

#### Ignoring the ABI

Generating a correct import table does not arrange function arguments or stack
state. The call site must follow the imported procedure's platform ABI.

### Practical Import Rules

1. Create one immutable import set for the image.
2. Use `pe_import_use32*` with PE32 and `pe_import_use64*` with PE64.
3. Prefer local slot aliases that match the source naming style.
4. Declare one writable, non-executable `format_imports` section.
5. Let `format_pe_import_section` emit and finalize the complete `.idata`.
6. Call through the generated IAT label with an indirect memory operand.
7. Follow the correct Windows calling convention at every call site.
8. Preserve the latest import map returned by each declaration.
9. Depend on labels and names, not generated table offsets.
10. Keep ASLR and absolute-address relocation requirements explicit.

Chapter 7 changes the image role from EXE to DLL, exports callable symbols, and
adds the base relocations required for rebasing absolute fields.

## 7. DLL Exports and Base Relocations

A dynamic-link library is a PE image that another process loads into its own
address space. The DLL may export functions, data, or both. Its entry point is
loader-facing initialization code and is separate from the symbols that
callers resolve by name.

The ordinary facade uses the same PE32 and PE64 section lifecycle as an
executable. The main differences are:

- select `format_pe_dll` instead of `format_pe_exe`;
- provide an export list and a `format_exports` section;
- provide base relocations for absolute fields that must survive rebasing;
- write an entry routine suitable for DLL loading.

### A DLL Entry Is Not an Export

Windows may call the DLL entry point while loading or unloading the module.
The entry receives platform-defined arguments and returns a Boolean result.
The minimal entry below accepts every notification:

```text
dll_entry:
    mov eax, 1
    ret
```

The entry label is still bound through `format_entry`. Exported functions are
declared separately and may use completely different labels.

Keep DLL entry work small. Complex initialization, imported calls, locking,
thread creation, and caller-specific setup are better placed in explicit
exported functions.

### Build an Export List

Exports are an immutable list:

```text
const exports0: list = pe_export_new()
const exports1: list = pe_export_use64(
    exports0,
    "answer_value",
    "xir_answer_value"
)
const exports: list = pe_export_use64(
    exports1,
    "answer",
    "xir_answer"
)
```

Each declaration connects:

```text
target label       address inside the DLL
export name        name visible to external callers
```

Use `pe_export_use32` with PE32 and `pe_export_use64` with PE64. Function and
data exports use the same declaration because an export-table entry records an
RVA, not a source-language type.

The facade sorts export names when it creates the PE name-pointer table.
Callers may declare exports in the source order that best expresses the
program. They do not need to reproduce the table's lexical ordering rule.

### A Relocatable PE64 DLL

This DLL exports a function named `xir_answer` and an integer named
`xir_answer_value`. The function follows an absolute pointer stored inside the
image, so that pointer receives a base relocation:

```asm
import("format/format.inc");
x86.use64();

const exports0: list = pe_export_new()
const exports1: list = pe_export_use64(
    exports0,
    "answer_value",
    "xir_answer_value"
)
const exports: list = pe_export_use64(
    exports1,
    "answer",
    "xir_answer"
)

const image0: map = format_pe64(
    format_pe_dll
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_required,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".edata",
            format_exports | format_readable
        ),
        format_section(
            ".reloc",
            format_fixups | format_readable | format_discardable
        )
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
dll_entry:
    mov eax, 1
    ret

answer:
    mov rax, [rel answer_pointer]
    mov eax, [rax]
    ret

answer_pointer:
    dq(0);
format_section_end(image0, ".text");

format_section_begin(image0, ".data");
answer_value:
    dd(42);
format_section_end(image0, ".data");

format_pe_export_section(
    image0,
    ".edata",
    exports,
    "answer.dll"
);

const relocs0: list = pe_reloc_new()
const relocs: list = format_pe_reloc_add(
    image0,
    relocs0,
    answer_pointer
)
format_pe_reloc_section(image0, ".reloc", relocs);

const image: map = format_entry(image0, dll_entry)
format_finish(image);

defer {
    store.u64(answer_pointer, answer_value);
}
```

Assemble it as a 64-bit DLL:

```powershell
xirasm answer.asm --target x86-64 -o answer.dll
```

The DLL contains:

- a DLL file-header flag;
- a loader entry at `dll_entry`;
- an export named `xir_answer` whose RVA points to `answer`;
- an export named `xir_answer_value` whose RVA points to `answer_value`;
- one DIR64 base relocation for `answer_pointer`;
- dynamic-base, high-entropy-VA, and NX-compatible image flags.

### The Pointer Value and Relocation Are Separate

Three operations cooperate in the example.

First, the source reserves a real 64-bit field:

```text
answer_pointer:
    dq(0)
```

Second, the finalizer writes the pointer's preferred-base value after layout:

```text
store.u64(answer_pointer, answer_value)
```

Third, the relocation list tells the loader that this field must move when the
image base changes:

```text
format_pe_reloc_add(image0, relocs0, answer_pointer)
```

The stored pointer is the current value. The DIR64 record is the loader's
instruction for applying a base delta. Neither operation replaces the other.

The function itself reaches `answer_pointer` with a RIP-relative instruction,
so that instruction does not contain an absolute image address. The pointer
stored in the slot is absolute and therefore needs the relocation.

### ASLR Policies on DLLs

`format_pe_aslr_required` is useful when rebasing is a required property. It
rejects a plan without a `format_fixups` section.

`format_pe_aslr_auto` enables the dynamic-base flag when the plan contains that
section. It is appropriate when one source shape may or may not contain
absolute relocatable fields.

`format_pe_aslr_disabled` keeps the dynamic-base flag clear. Use it only for a
DLL intentionally tied to its preferred image base.

An existing `.reloc` section does not make arbitrary absolute fields safe. Each
field that must follow the loaded image needs its own relocation declaration.

### PE32 Uses HIGHLOW Relocations

The PE32 workflow is the same, with width-specific values:

| Concern | PE32 DLL | PE64 DLL |
| --- | --- | --- |
| Export declaration | `pe_export_use32` | `pe_export_use64` |
| Absolute pointer storage | `dd(0)` | `dq(0)` |
| Final backfill | `store.u32` | `store.u64` |
| Generated base relocation | HIGHLOW | DIR64 |
| Default image base | `0x00400000` | `0x0000000140000000` |
| High-entropy-VA flag | not applicable | enabled for relocatable images |

`format_pe_reloc_add` selects HIGHLOW or DIR64 from the plan kind. Ordinary
source passes the field label and does not choose the numeric relocation type.

Exported functions must follow the calling convention expected by their
callers. A PE64 export normally follows the Windows x64 calling convention.
A PE32 export must state and implement its chosen 32-bit convention as part of
the external interface.

### Call the DLL from Another Language

Any language that can load a Windows DLL and resolve an export can consume the
generated image. The following C# program calls the function export and reads
the data export:

```csharp
using System;
using System.Runtime.InteropServices;

internal static class Program
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryW(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    private static extern IntPtr GetProcAddress(
        IntPtr module,
        string name
    );

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int Answer();

    private static int Main()
    {
        IntPtr module = LoadLibraryW("answer.dll");
        if (module == IntPtr.Zero)
            return 1;

        IntPtr functionAddress = GetProcAddress(module, "xir_answer");
        IntPtr dataAddress = GetProcAddress(module, "xir_answer_value");
        if (functionAddress == IntPtr.Zero || dataAddress == IntPtr.Zero)
            return 2;

        Answer answer =
            Marshal.GetDelegateForFunctionPointer<Answer>(functionAddress);
        int value = Marshal.ReadInt32(dataAddress);

        return answer() == 42 && value == 42 ? 0 : 3;
    }
}
```

The external caller sees only the DLL file, export names, and calling
convention. It does not depend on XIRASM labels, section rows, or relocation
table positions.

### Loading at a Different Base

When the preferred address is unavailable, the loader selects another base and
computes:

```text
delta = loaded base - preferred base
```

For every DIR64 or HIGHLOW entry, it adds that delta to the stored field. In
the example, `answer_pointer` then points to the relocated `answer_value`, so
the exported function still returns 42.

This is the runtime meaning of the relocation directory. Structural presence
alone is not enough; the relocation must identify the correct field and the
field must contain the correct preferred-base value.

### Common DLL Mistakes

#### Exporting the Entry Routine Accidentally

The loader entry and public API are separate interfaces. Export only labels
that external callers should use.

#### Omitting the Export Section

`format_pe_export_section` requires a declared section whose purpose is
`format_exports`.

#### Opening `.edata` or `.reloc` Manually

The ordinary export and relocation helpers manage those section lifecycles.
Do not wrap them in additional section begin/end calls.

#### Forgetting the Backfill

A relocation record does not initialize the field. Write the stable preferred
address into every raw absolute slot.

#### Forgetting the Relocation

A correct pointer at the preferred base may become invalid after rebasing.
Declare every absolute field that follows the image.

#### Exporting an ABI-Incompatible Function

The export table publishes an address, not a calling convention. The assembly
routine and foreign declaration must agree on arguments, result, stack state,
and preserved registers.

### Practical DLL Rules

1. Select `format_pe_dll` and provide a small loader entry.
2. Keep exported functions and data separate from the DLL entry.
3. Build one immutable export list from target labels and public names.
4. Declare a readable `format_exports` section.
5. Let `format_pe_export_section` generate the complete export directory.
6. Use fixed-width placeholders for absolute pointer fields.
7. Backfill each pointer with its stable preferred-base value.
8. Add every relocatable absolute field through `format_pe_reloc_add`.
9. Emit one readable, discardable `format_fixups` section.
10. Validate exports through a real foreign caller and a nonpreferred load
    address.

Chapter 8 adds resource data and optional PE checksums without making those
features part of the minimal EXE or DLL path.

## 8. PE Resources and Checksums

Resources and checksums are optional parts of a PE image. They solve different
problems:

- resources attach structured application data to the image;
- the PE checksum records a checksum of the final physical file.

Neither feature belongs in the code section. The ordinary facade gives
resources their own planned section and calculates the checksum only after the
image bytes are stable.

### Resources Use a Dedicated Section

Declare a readable resource section with the `format_resources` purpose:

```text
format_section(".rsrc", format_resources | format_readable)
```

Resource data is normally read by the operating system or application code. It
does not need write or execute permission.

The ordinary helper owns the section lifecycle:

```text
format_pe_resource_section(image, ".rsrc", "app.res")
```

It performs the complete resource operation:

1. opens the declared resource section;
2. derives the section RVA from the final PE layout;
3. parses the compiled resource records;
4. builds the type, name, and language directory tree;
5. writes resource data entries and payloads;
6. closes the section;
7. registers the PE resource data-directory fields.

Do not open `.rsrc` manually around this call. Ordinary source supplies the
section name and compiled resource path, not a resource RVA or directory
offset.

### Use a Compiled Resource File

`format_pe_resource_section` accepts a compiled `.res` file. It does not accept
an `.rc` script and it does not embed the `.res` file as one opaque payload.

A resource compiler first converts the human-written resource script and its
input files into compiled resource records. XIRASM then reads those records and
rebuilds the PE resource hierarchy.

One compiled file may contain:

- numeric or named resource types;
- numeric or named resource identifiers;
- multiple numeric language identifiers;
- several payloads that share a type or name.

The facade orders the directory entries deterministically, preserves each
payload's exact size, and applies the alignment required by the PE resource
format. Empty compiled records do not become resource leaves.

Relative paths use the same source-relative resolution rules as other file
APIs. A source file beside `app.res` can therefore use:

```text
format_pe_resource_section(image, ".rsrc", "app.res")
```

Combine all resources for one image into the compiled file used by the single
declared `format_resources` section.

### A PE64 Executable with Resources and a Checksum

This example adds a compiled resource file to a small PE64 executable and then
calculates the checksum of the completed image:

```asm
import("format/format.inc");

const image0: map = format_pe64(
    format_pe_exe |
    format_pe_console |
    format_pe_nx |
    format_pe_aslr_disabled,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".rsrc",
            format_resources | format_readable
        )
    )
)

format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

format_pe_resource_section(
    image0,
    ".rsrc",
    "app.res"
);

const image: map = format_entry(image0, start)
format_finish(image);
format_pe_checksum(image);
```

The image plan determines that `.rsrc` is the second section. The source does
not calculate its row, raw pointer, RVA, directory offset, or final size.

The checksum call also does not receive a section list. It reads the declared
PE plan and folds the header plus every section's physical bytes in declaration
order.

### The Checksum Covers the Final File

`format_pe_checksum(image)` registers the checksum calculation as a final
operation. It:

1. clears the checksum field while reading the PE headers;
2. folds each declared section's file-backed bytes;
3. reduces the accumulated 16-bit sum;
4. adds the final physical file size;
5. stores the result in the optional header.

Memory-only BSS contributes no file bytes. Its logical size still affects the
loaded image, but it does not create data for the checksum to read.

The PE checksum is not a digital signature or a cryptographic integrity proof.
It is a format-defined checksum field. Signing, trust, and tamper resistance
are separate concerns.

### Register Byte Backfills before the Checksum

Finalizers run in registration order. Any finalizer that changes output bytes
must be registered before `format_pe_checksum`.

For example, an absolute pointer backfill belongs before the checksum:

```text
format_finish(image)

defer {
    store.u64(pointer_slot, target);
}

format_pe_checksum(image)
```

The checksum then observes the stored pointer value. A read-only assertion may
be registered afterward because it does not change the file.

Do not modify, append, sign, or otherwise rewrite the file after calculating
the checksum unless the later operation also updates the checksum according to
its own file-processing rules.

### Resources Work in EXEs and DLLs

The same resource helper works with PE32 and PE64 plans, and with both EXE and
DLL image roles. The compiled resource representation is not pointer-width
dependent.

The checksum helper also selects no bitness-specific user workflow. PE32 and
PE64 place the checksum field at the same relative optional-header location,
and the facade applies the correct image layout automatically.

Resources remain independent from imports, exports, and base relocations. A
larger image may declare all of these generated section purposes:

```text
list.of(
    format_section(
        ".text",
        format_code | format_readable | format_executable
    ),
    format_section(
        ".idata",
        format_imports | format_readable | format_writeable
    ),
    format_section(
        ".edata",
        format_exports | format_readable
    ),
    format_section(
        ".rsrc",
        format_resources | format_readable
    ),
    format_section(
        ".reloc",
        format_fixups | format_readable | format_discardable
    )
)
```

Each generated helper owns its matching section lifecycle. The checksum is
registered only after those sections and all byte-changing backfills are
complete.

### Common Resource and Checksum Mistakes

#### Passing an `.rc` Script

The resource helper reads compiled `.res` records. Compile the resource script
before assembling the PE image.

#### Treating a `.res` File as Raw Data

The helper parses the records and rebuilds a PE resource tree. Use ordinary
data emission when the desired result is merely an opaque byte array.

#### Declaring the Wrong Section Purpose

`format_pe_resource_section` requires a section declared with
`format_resources`.

#### Opening `.rsrc` Manually

The ordinary resource helper opens, emits, finalizes, and closes the section.
Do not add another begin/end pair around it.

#### Calculating the Checksum Too Early

Register every byte-changing `defer` block first. A checksum calculated from
placeholder bytes becomes stale when a later finalizer writes the real value.

#### Treating the Checksum as Authentication

The checksum detects no malicious replacement by itself. Use the appropriate
signing and verification system when authenticity matters.

### Practical Resource and Checksum Rules

1. Compile resource scripts into one `.res` input for the image.
2. Declare one readable `format_resources` section.
3. Let `format_pe_resource_section` own the complete `.rsrc` lifecycle.
4. Pass file paths, names, and labels rather than resource RVAs or table rows.
5. Finish imports, exports, resources, and relocations before the checksum.
6. Register every final byte backfill before `format_pe_checksum`.
7. Treat BSS as memory size, not file bytes.
8. Calculate a checksum only when the output workflow requires it.
9. Do not confuse the PE checksum with a digital signature.
10. Recalculate the checksum after any later operation that changes covered
    bytes.

Chapter 9 moves from loadable PE images to COFF object files, where sections,
symbols, and relocations describe work for a linker rather than a loader.

## 9. COFF32 and COFF64 Objects

A COFF object is not a program that the operating system can load directly. It
is a collection of sections, symbols, and relocation requests for a linker.

This changes the format lifecycle:

- there is no PE optional header;
- there is no subsystem or image base;
- there is no executable entry point;
- public symbols identify definitions supplied by this object;
- external symbols identify definitions expected from other objects or
  libraries;
- relocations tell the linker which encoded fields depend on those symbols.

The ordinary facade keeps section numbers, symbol indexes, relocation rows, and
table file offsets internal.

### Create an Object Plan

Use `format_coff32` for i386 objects and `format_coff64` for AMD64 objects:

```text
const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        )
    )
)
```

Descriptor order becomes COFF section order. The facade derives the section
count and writes one section header for each descriptor.

Object sections use the same ordinary lifecycle as PE sections:

```text
format_begin(object0)
format_section_begin(object0, ".text")
...
format_section_end(object0, ".text")
```

Do not call `format_entry`. An object publishes symbols; the final executable's
entry point is selected when objects are linked into an image.

### Public Symbols Describe Definitions

`format_coff_public` declares a symbol defined in one of the object's sections:

```text
format_coff_public(
    "main",
    ".text",
    text_start,
    main,
    coff_sym_type_function
)
```

The arguments identify:

1. the link-visible symbol name;
2. the declared section name;
3. a label at the start of that section;
4. the symbol label;
5. the COFF symbol type.

The facade calculates the symbol's section number and section-relative value.
The source does not pass either numeric field.

Use `coff_sym_type_function` for callable code and
`coff_sym_type_null` for ordinary data.

### External Symbols Describe Requirements

`format_coff_extern` declares a symbol that must be supplied elsewhere:

```text
format_coff_extern("helper", coff_sym_type_function)
```

The generated symbol has no defining section. A linker later searches the other
objects and libraries in the link for a matching definition.

The current ordinary COFF workflow uses names that fit in the eight-byte COFF
name field. Keep section, public, external, and relocation target names within
that boundary.

### Relocations Identify Encoded Patch Fields

An external call contains a four-byte displacement that cannot be finalized
until the linker knows the target address. Emit a placeholder and label the
field itself:

```text
db(0xe8)
helper_disp:
dd(0)
```

The relocation refers to the displacement label, not the call opcode:

```text
format_coff_reloc(
    ".text",
    text_start,
    helper_disp,
    "helper",
    coff_rel_amd64_rel32
)
```

The facade derives:

- the relocation's section number from `.text`;
- its section-relative offset from `helper_disp - text_start`;
- the symbol-table index by finding `helper`;
- the relocation-table file position during finalization.

The relocation type must match the architecture and encoded field. A relative
call uses:

| Object kind | Relative-call relocation |
| --- | --- |
| COFF32 | `coff_rel_i386_rel32` |
| COFF64 | `coff_rel_amd64_rel32` |

### Attach Symbols and Relocations to the Plan

Symbol and relocation declarations are ordinary compile-time lists:

```text
const symbols: list = list.of(...)
const relocs: list = list.of(...)
```

Attach them with `format_coff_tables`:

```text
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object)
```

The function returns a new plan. Preserve that returned value and pass it to
`format_finish`.

During finish, the facade:

1. groups relocations by their declared section;
2. resolves each relocation target by symbol name;
3. emits relocation rows;
4. emits the symbol table in declaration order;
5. writes the minimal COFF string-table terminator;
6. backfills the file header and section relocation fields.

### A Linkable COFF64 Object

This object defines `main`, initialized data, and BSS storage. It calls an
external function named `helper` through an AMD64 relative relocation:

```asm
import("format/format.inc");

const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        )
    )
)

format_begin(object0);

format_section_begin(object0, ".text");
text_start:
main:
    sub rsp, 40
    db(0xe8);
helper_disp:
    dd(0);
    add rsp, 40
    ret
format_section_end(object0, ".text");

format_section_begin(object0, ".data");
data_start:
answer:
    dd(42);
format_section_end(object0, ".data");

format_section_begin(object0, ".bss");
bss_start:
scratch:
    rb(64);
format_section_end(object0, ".bss");

const symbols: list = list.of(
    format_coff_public(
        "main",
        ".text",
        text_start,
        main,
        coff_sym_type_function
    ),
    format_coff_public(
        "answer",
        ".data",
        data_start,
        answer,
        coff_sym_type_null
    ),
    format_coff_public(
        "scratch",
        ".bss",
        bss_start,
        scratch,
        coff_sym_type_null
    ),
    format_coff_extern("helper", coff_sym_type_function)
)

const relocs: list = list.of(
    format_coff_reloc(
        ".text",
        text_start,
        helper_disp,
        "helper",
        coff_rel_amd64_rel32
    )
)

const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);
```

The stack adjustment reserves the Windows x64 shadow space and aligns the stack
for the external call. The object itself does not define `helper`.

A C source can provide the missing definition:

```c
extern unsigned char scratch[64];

int helper(void) {
    scratch[63] = 7;
    return scratch[63] == 7 ? 0 : 1;
}
```

Compile the C source to a COFF64 object and link it with the XIRASM object. The
linker resolves the undefined `helper` symbol, applies the REL32 relocation,
and produces the final executable.

The `.bss` section header reports a size of 64 and a raw-data pointer of zero.
The object stores no 64-byte payload. The linker allocates the storage in the
final image, and the C function proves that the last byte is writable.

### COFF32 Uses the Same Plan Model

The 32-bit workflow changes the object kind, symbol spelling required by the
chosen ABI, and relocation type:

```asm
import("format/format.inc");

const object0: map = format_coff32(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)

format_begin(object0);

format_section_begin(object0, ".text");
text_start:
_main:
    db(0xe8);
helper_disp:
    dd(0);
    ret
format_section_end(object0, ".text");

const symbols: list = list.of(
    format_coff_public(
        "_main",
        ".text",
        text_start,
        _main,
        coff_sym_type_function
    ),
    format_coff_extern("_helper", coff_sym_type_function)
)

const relocs: list = list.of(
    format_coff_reloc(
        ".text",
        text_start,
        helper_disp,
        "_helper",
        coff_rel_i386_rel32
    )
)

const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);
```

The leading underscores in this example follow a common 32-bit C ABI naming
convention. They are symbol names, not an automatic transformation performed
by the COFF facade. Match the names expected by the compiler and linker used by
the project.

### BSS Must Remain File-Empty

An uninitialized-data descriptor gives the section the COFF uninitialized-data
characteristic. A reserve-only section advances its logical size without
writing payload bytes. The section header records that logical size while its
raw-data pointer remains zero.

The ordinary facade keeps two coordinates:

- the potential cursor preserves the logical extent of reserved storage;
- the real cursor marks the next physical file position.

Relocation and symbol tables begin at the real cursor. This keeps the object
compact and prevents metadata from being misreported as BSS raw data.

### Common COFF Object Mistakes

#### Calling `format_entry`

COFF objects do not contain an executable entry. Publish a public function
symbol and let the final link select the entry point.

#### Discarding the Updated Plan

`format_coff_tables` returns the plan that owns the symbol and relocation
lists. Finishing the earlier binding omits those tables.

#### Relocating the Opcode

For a relative call, the relocation belongs to the four-byte displacement
field after the opcode.

#### Using the Wrong Architecture's Relocation

Use the i386 relocation constants with `format_coff32` and the AMD64 constants
with `format_coff64`.

#### Omitting the External Symbol

A relocation target must appear in the symbol list. Declare an unresolved
target with `format_coff_extern`.

#### Duplicating a Symbol Name

The ordinary facade rejects duplicate public or external names because named
relocation lookup would be ambiguous.

#### Writing Bytes into BSS

Use reserve operations for uninitialized data. Initialized bytes belong in a
`format_data` section.

#### Assuming a Calling Convention

The symbol table describes names and locations, not argument passing. Assembly
code, compiled objects, and the final linker invocation must agree on the ABI.

### Practical COFF Object Rules

1. Choose `format_coff32` or `format_coff64` to match the target linker inputs.
2. Declare code, initialized data, and BSS as separate sections.
3. Define a stable start label for every section referenced by symbols or
   relocations.
4. Declare every link-visible definition with `format_coff_public`.
5. Declare every unresolved requirement with `format_coff_extern`.
6. Place relocation labels on encoded patch fields, not surrounding
   instructions.
7. Select relocation types that match both the architecture and field
   encoding.
8. Attach the final symbol and relocation lists with `format_coff_tables`.
9. Finish the updated plan without adding an executable entry.
10. Validate the object by linking it with a real consumer or provider object.

Chapter 10 returns to loadable images and introduces ELF32 and ELF64
executables with compact file layout and independently aligned LOAD segments.

## Part III: ELF Formats

## 10. ELF32 and ELF64 Executables

An ELF executable is a loadable image for a system that implements the ELF
process model. The file header identifies the architecture and entry address.
Program headers describe the byte ranges and memory ranges that the loader
maps into the process.

This chapter builds fixed-address executables:

- `format_elf32(format_elf_exec, ...)` creates an i386 `ET_EXEC` image;
- `format_elf64(format_elf_exec, ...)` creates an AMD64 `ET_EXEC` image;
- every ordinary descriptor becomes one `PT_LOAD` program header;
- `format_entry` binds the address where execution begins;
- the facade derives every program-header count, offset, address, size, flag,
  and alignment field.

Position-independent images and dynamic imports are covered in Chapter 11.

### Choose the ELF Class and Execution Mode

An ELF plan receives the execution mode and an ordered segment list:

```text
const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        ),
        format_segment(
            ".data",
            format_load | format_readable | format_writeable
        )
    )
)
```

Use `format_elf32` for 32-bit x86 code and `format_elf64` for 64-bit x86 code.
The selected format controls the ELF class, machine type, header widths, and
default load base.

The ordinary fixed-address defaults are:

| Plan | ELF class | Machine | Default image base |
| --- | --- | --- | --- |
| `format_elf32` | ELF32 | i386 | `0x08048000` |
| `format_elf64` | ELF64 | AMD64 | `0x00400000` |

`format_elf32` currently accepts only `format_elf_exec`. `format_elf64` also
supports position-independent mode, but that mode changes the loading and
dynamic-linking model and belongs in the next chapter.

### ELF Executables Use LOAD Segments

The loader does not organize an executable by source-level section names. It
maps the ranges described by program headers.

The ordinary executable facade therefore uses segment descriptors:

```text
format_segment(
    ".text",
    format_load | format_readable | format_executable
)
```

Every ordinary executable segment has the `format_load` purpose. Permissions
describe the memory mapping:

| Content | Recommended permissions |
| --- | --- |
| instructions | readable and executable |
| mutable initialized data | readable and writeable |
| BSS | readable and writeable |
| constants | readable |

Descriptor order becomes program-header order. Open and close content with:

```text
format_segment_begin(image0, ".text")
...
format_segment_end(image0, ".text")
```

Do not use `format_section_begin` for an ELF executable plan. Sections are the
linker-facing unit used by object files. LOAD segments are the runtime-facing
unit used here.

### A Fixed-Address ELF64 Executable

The following program verifies initialized data, writes the final byte of BSS,
reads a constant placed after BSS, and exits through the Linux x86-64 system
call interface:

```asm
import("format/format.inc");

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        ),
        format_segment(
            ".data",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".bss",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".rodata",
            format_load | format_readable
        )
    )
)

format_begin(image0);

format_segment_begin(image0, ".text");
start:
    mov eax, [rel answer]
    cmp eax, 42
    jne failed

    lea rbx, [rel scratch]
    mov byte [rbx + 127], 7
    cmp byte [rbx + 127], 7
    jne failed

    mov eax, [rel marker]
    cmp eax, 0x11223344
    jne failed

    xor edi, edi
exit:
    mov eax, 60
    syscall
failed:
    mov edi, 1
    jmp exit
format_segment_end(image0, ".text");

format_segment_begin(image0, ".data");
answer:
    dd(42);
format_segment_end(image0, ".data");

format_segment_begin(image0, ".bss");
scratch:
    rb(128);
format_segment_end(image0, ".bss");

format_segment_begin(image0, ".rodata");
marker:
    dd(0x11223344);
format_segment_end(image0, ".rodata");

const image: map = format_entry(image0, start)
format_finish(image);
```

The program uses RIP-relative memory references for labels in other LOAD
segments. Forward conditional branches such as `jne failed` are resolved by
the assembler; they do not require a manual `near` qualifier.

The `exit` system call expects:

- system call number `60` in `eax`;
- process status in `edi`.

No runtime library or dynamic loader metadata is required because the program
uses the kernel interface directly.

### File Layout and Memory Layout Are Different

The ELF64 example produces four LOAD mappings. Their exact sizes depend on the
encoded instructions, but the relationship between them is stable:

| Segment | File bytes | Memory bytes | Permissions |
| --- | --- | --- | --- |
| `.text` | instructions | instructions | read, execute |
| `.data` | initialized data | initialized data | read, write |
| `.bss` | zero | reserved storage | read, write |
| `.rodata` | constants | constants | read |

For this source, the file is 368 bytes. Its LOAD layout is:

| Segment | File offset | Virtual address | File size | Memory size |
| --- | --- | --- | --- | --- |
| `.text` | `0x120` | `0x400120` | `0x48` | `0x48` |
| `.data` | `0x168` | `0x401168` | `0x04` | `0x04` |
| `.bss` | `0x16C` | `0x40216C` | `0x00` | `0x80` |
| `.rodata` | `0x16C` | `0x40316C` | `0x04` | `0x04` |

The BSS and following read-only segment may share the same file offset because
BSS has no file bytes. They do not share a virtual address.

Every LOAD preserves page congruence:

```text
p_vaddr % p_align == p_offset % p_align
```

The facade advances the logical address to a suitable page while continuing
the physical file at the real end of the preceding bytes. It does not insert a
page of zero bytes between LOAD segments.

This is why the file remains hundreds of bytes rather than growing by several
kilobytes for every segment.

### BSS Is Memory without File Payload

A reserve-only LOAD segment records:

```text
p_filesz = 0
p_memsz  = reserved logical size
```

The loader creates writable zero-initialized memory for that range. The
`scratch` access in the example proves that the final reserved byte is mapped
and writeable.

Use reserve operations such as `rb` inside the BSS segment. Initialized bytes
belong in a file-backed data segment.

Placing another file-backed segment after BSS is valid. The facade keeps the
next file offset compact while assigning a later virtual page, so the new
mapping cannot overlap the BSS memory range.

### Bind the Entry after Its Label Exists

The entry label belongs to the code segment:

```text
start:
    ...

const image: map = format_entry(image0, start)
format_finish(image)
```

`format_entry` returns an updated plan. Pass that returned value to
`format_finish`.

For an ELF executable, the entry field stores the final virtual address, not a
file offset and not an image-relative value.

The facade requires a nonzero entry before finishing an ELF32 or ELF64
executable.

### ELF32 Uses the Same Segment Model

ELF32 changes the header width, machine type, address width, and system call
ABI. The plan lifecycle remains the same.

The source must select 32-bit x86 instruction mode:

```asm
import("format/format.inc");

x86.use32();

const image0: map = format_elf32(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        ),
        format_segment(
            ".data",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".bss",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".rodata",
            format_load | format_readable
        )
    )
)

format_begin(image0);

format_segment_begin(image0, ".text");
start:
    mov eax, [answer]
    cmp eax, 42
    jne failed

    mov byte [scratch + 63], 7
    cmp byte [scratch + 63], 7
    jne failed

    mov eax, [marker]
    cmp eax, 0x11223344
    jne failed

    xor ebx, ebx
exit:
    mov eax, 1
    int 0x80
failed:
    mov ebx, 1
    jmp exit
format_segment_end(image0, ".text");

format_segment_begin(image0, ".data");
answer:
    dd(42);
format_segment_end(image0, ".data");

format_segment_begin(image0, ".bss");
scratch:
    rb(64);
format_segment_end(image0, ".bss");

format_segment_begin(image0, ".rodata");
marker:
    dd(0x11223344);
format_segment_end(image0, ".rodata");

const image: map = format_entry(image0, start)
format_finish(image);
```

The 32-bit Linux exit interface uses system call number `1` in `eax` and the
status value in `ebx`.

This example produces a 269-byte ELF32 executable. Its BSS LOAD has zero file
size and a memory size of 64 bytes. The read-only LOAD after BSS continues at
the same physical file offset and a later virtual page.

A 64-bit Linux installation may require IA32 execution support before it can
run a 32-bit executable. This is an operating-system configuration issue, not
an ELF layout change.

### Program Headers Are the Runtime Contract

The fixed-address executables in this chapter do not need a section-header
table. The loader uses:

- the ELF file header;
- the entry virtual address;
- the ordered program-header table;
- the LOAD offsets, addresses, sizes, permissions, and alignment.

The descriptor names such as `.text` and `.bss` are source-level plan names.
They let the program open the intended segment and let diagnostics identify
mistakes. They are not emitted as runtime section names in these compact
images.

Use ELF object files when a linker needs named sections, symbol tables, and
relocation sections. Chapter 12 covers that workflow.

### Fixed Executables Do Not Provide Dynamic Imports

A direct system call needs no imported symbol. A call to a C library or another
shared library requires additional ELF metadata:

- an interpreter;
- dynamic string and symbol tables;
- PLT and GOT state;
- dynamic relocations;
- dependency records.

Do not call an unresolved library symbol from the fixed executable shown here.
Chapter 11 introduces the ordinary ELF64 dynamic-import workflow.

### Common ELF Executable Mistakes

#### Omitting `format_elf_exec`

The ordinary constructor requires one explicit execution mode. Chapter 10 uses
`format_elf_exec`.

#### Using Sections Instead of LOAD Segments

An ELF executable plan is opened with `format_segment_begin` and closed with
`format_segment_end`.

#### Omitting `format_load`

Every ordinary executable segment must have the LOAD purpose in addition to
its permissions.

#### Making Data Executable

Give write permission only to mutable data and BSS. Keep constants read-only
and keep writable data non-executable.

#### Writing Initialized Bytes into BSS

Reserve BSS storage with `rb` or another reserve operation. Move initialized
values into a file-backed data segment.

#### Adding Manual Page Padding

Do not write zero-filled pages between segments. The facade derives congruent
virtual addresses while keeping physical file bytes compact.

#### Discarding the Updated Entry Plan

Finish the value returned by `format_entry`, not the earlier plan binding.

#### Expecting Segment Names in the File

The compact executable is driven by program headers. Source-level segment names
are not a section-header string table.

#### Calling a Library without Dynamic Metadata

Direct kernel calls and dynamically imported library calls are different
workflows. Use the dynamic-import facade described in Chapter 11 when a symbol
must be resolved by the runtime linker.

### Practical ELF Executable Rules

1. Use `format_elf32` or `format_elf64` to match the instruction width.
2. Pass `format_elf_exec` for the fixed-address workflow in this chapter.
3. Describe code, mutable data, BSS, and constants as separate LOAD segments.
4. Give each LOAD only the permissions its contents require.
5. Use `format_segment_begin` and `format_segment_end` in descriptor order.
6. Reserve BSS storage without emitting initialized bytes.
7. Let the facade derive file offsets, virtual addresses, and page congruence.
8. Define the entry label inside executable code.
9. Finish the updated plan returned by `format_entry`.
10. Use direct system calls only when no dynamic runtime dependency is needed.

Chapter 11 introduces ELF64 position-independent executables and dynamic
imports, including the interpreter, PLT, GOT, and runtime relocation model.

## 11. Position-Independent Executables and Dynamic Imports

ELF64 supports two additional executable workflows in the ordinary format
facade:

- a position-independent executable that uses relative addressing and direct
  system calls;
- a fixed-address executable that imports functions through generated PLT and
  GOT state.

These are separate workflows. Selecting PIE changes how the loader may place
the image, but it does not automatically add a runtime interpreter or imported
symbols. Adding a dynamic import table generates the interpreter, dynamic
symbol data, PLT, GOT, and relocation records, but the current ordinary import
workflow requires fixed-address EXEC mode.

This chapter explains both models and the boundary between them.

### Select ELF64 PIE Explicitly

Create a position-independent plan with:

```text
format_elf64(format_elf_pie, segments)
```

The resulting ELF header uses `ET_DYN` and an image base of zero. LOAD virtual
addresses are offsets within the image rather than addresses derived from the
fixed ELF64 base used by Chapter 10.

The operating system chooses the runtime load address. It adds that address to
the entry value and to the LOAD virtual addresses when mapping the executable.

The ordinary PIE workflow currently supports ELF64 only. Passing
`format_elf_pie` to `format_elf32` is rejected.

### Position Independence Is a Source-Code Property

An `ET_DYN` header does not make absolute values position-independent.

Code should reach internal labels through PC-relative instructions:

```text
lea rsi, [rel message]
mov eax, [rel value]
call helper
```

A direct relative branch or call remains valid after the complete image moves,
because both the instruction and its target move by the same amount.

An absolute data field is different. For example, a raw `dq(start)` stores the
link-time value of `start`. The minimal PIE workflow in this chapter does not
generate a dynamic relocation for that field, so the runtime loader has no
instruction to add the chosen load address.

Use relative code references, relative offsets, or a runtime calculation when
building a PIE without dynamic relocations.

### A Multi-Segment ELF64 PIE

This example contains executable code, BSS, and read-only data. The code uses
RIP-relative addressing for both data segments and therefore remains valid at
any load address.

```asm
import("format/format.inc");

const image0: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
start:
    lea rbx, [rel scratch]
    mov dword [rbx], 0x5a
    cmp dword [rbx], 0x5a
    jne failed

    mov eax, 1
    mov edi, 1
    lea rsi, [rel message]
    mov edx, message_end - message
    syscall

    xor edi, edi
    jmp finish

failed:
    mov edi, 1

finish:
    mov eax, 60
    syscall
format_segment_end(image0, ".text");

format_segment_begin(image0, ".bss");
scratch:
    rb(64);
format_segment_end(image0, ".bss");

format_segment_begin(image0, ".rodata");
message:
    db("XIRASM PIE", 10);
message_end:
format_segment_end(image0, ".rodata");

const image: map = format_entry(image0, start)
format_finish(image);
```

The generated file is 316 bytes and contains three LOAD entries:

- an RX LOAD for the code;
- an RW LOAD with file size zero and memory size 64 for BSS;
- an R LOAD for the message.

The BSS and read-only LOADs share the next compact physical file position, but
occupy different virtual pages. Every LOAD still satisfies the ELF rule that
its virtual address and file offset have the same value modulo the page
alignment.

The program writes to BSS, reads the message through a relative address, prints
it, and exits successfully after being loaded as an `ET_DYN` executable.

### PIE Does Not Require a Dynamic Linker

The previous example makes Linux system calls directly. It has no imported
library symbols and therefore needs no:

- `PT_INTERP`;
- `PT_DYNAMIC`;
- dynamic symbol or string table;
- PLT or GOT;
- dynamic relocation table.

This is a position-independent executable, but not a dynamically linked
executable.

The distinction matters because PIE describes image placement, while dynamic
linking describes runtime symbol resolution. A file may need one, both, or
neither. The current ordinary facade implements the two supported combinations
described in this chapter rather than treating them as one option.

### Declare a PLT Import

The ordinary dynamic-import workflow begins with a fixed ELF64 executable plan:

```text
format_elf64(format_elf_exec, segments)
```

Create one import declaration for each procedure:

```text
format_elfexe_import_plt(library, name, slot_label, plt_label)
```

The arguments identify:

- the shared-library name recorded by `DT_NEEDED`;
- the external symbol name searched by the runtime linker;
- the local GOT/PLT slot label;
- the local PLT entry label used by call instructions.

Collect declarations in a list and attach them to the plan:

```text
const image1: map = format_elfexe_tables(image0, imports)
```

Use `image1` for `format_begin`, segment lifecycle calls, `format_entry`, and
`format_finish`. It is the plan that owns the import declarations.

### A Fixed ELF64 Executable That Calls libc

The following executable imports `getpid` from `libc.so.6`. The procedure
takes no arguments, which keeps the example focused on the ELF import model.

```asm
import("format/format.inc");

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)
const imports: list = list.of(
    format_elfexe_import_plt(
        "libc.so.6",
        "getpid",
        "getpid_gotplt",
        "getpid_plt"
    )
)
const image1: map = format_elfexe_tables(image0, imports)
format_begin(image1);

format_segment_begin(image1, ".text");
start:
    call getpid_plt
    test eax, eax
    jle failed

    xor edi, edi
    jmp finish

failed:
    mov edi, 1

finish:
    mov eax, 60
    syscall
format_segment_end(image1, ".text");

const image: map = format_entry(image1, start)
format_finish(image);
```

This example generates a 768-byte ELF64 executable. At startup, the runtime
linker resolves `getpid`, updates its GOT/PLT slot, and transfers control
through `getpid_plt`. The program treats a positive process identifier as
success and exits with status zero.

### What the Import Facade Generates

The import declarations are enough for the ordinary facade to generate:

- a `PT_INTERP` entry for the ELF64 runtime interpreter;
- a `PT_DYNAMIC` entry;
- dynamic symbol and string tables;
- a dependency record for each distinct library;
- a PLT entry for each imported procedure;
- GOT/PLT state used by the runtime resolver;
- `R_X86_64_JUMP_SLOT` relocation records;
- dynamic tags that connect the tables.

The user does not calculate symbol indexes, table addresses, relocation rows,
or program-header positions.

The generated LOAD permissions keep executable and writable state separate:

- user code is RX;
- the generated PLT is RX;
- GOT and dynamic metadata are RW;
- no LOAD is simultaneously writable and executable.

The PLT and metadata remain physically adjacent in the compact file, while
their virtual addresses are placed on separate page-congruent LOAD mappings.

### Call the PLT Label

Call the local PLT label supplied to `format_elfexe_import_plt`:

```text
call getpid_plt
```

Do not write a direct call to an undefined external name. XIRASM needs the
local PLT label so the ordinary facade can connect the instruction to the
generated resolver entry.

The slot label names the corresponding GOT/PLT entry. It is useful when code
needs the resolved pointer itself, but an ordinary procedure call normally
uses the PLT label.

### Imported Procedures Still Use the Platform ABI

The format facade builds ELF metadata. It does not change the calling
convention of the imported function.

Before calling a library procedure:

- place arguments in the registers or stack locations required by the
  platform ABI;
- preserve registers required by that ABI;
- maintain the required stack alignment;
- interpret the return value according to the function contract.

The loader can resolve a symbol correctly while the call still fails because
the caller used the wrong ABI.

### The Interpreter Path Is Part of the File

The current ELF64 executable-import workflow records:

```text
/lib64/ld-linux-x86-64.so.2
```

The target system must provide a compatible interpreter at that path. A system
with a different runtime layout may reject the file before its entry point
runs.

This is separate from the `DT_NEEDED` library name. The interpreter loads the
executable's dynamic metadata and then locates dependencies such as
`libc.so.6`.

### Current Ordinary-Layer Boundary

The current ordinary facade supports:

- ELF64 PIE without generated dynamic imports;
- fixed-address ELF64 EXEC with PLT-based dynamic imports.

It does not currently attach `format_elfexe_tables` to:

- an ELF64 PIE plan;
- an ELF32 executable;
- an ELF32 PIE plan.

Those combinations are rejected instead of producing incomplete dynamic
metadata.

Do not work around this boundary by mixing the ordinary plan with
width-specific or row-oriented helpers. Direct format control belongs in the
separate advanced format guide.

### Common PIE and Dynamic-Import Mistakes

#### Storing an Absolute Internal Address in PIE Data

A raw pointer such as `dq(start)` is not automatically rebased in the minimal
PIE workflow. Use relative access or generate the required dynamic relocation
through an appropriate advanced workflow.

#### Using Absolute Addressing in PIE Code

Use forms such as `[rel label]` when code must access another part of the same
image.

#### Assuming PIE Adds Library Imports

`format_elf_pie` selects position-independent image placement. It does not add
an interpreter, imported symbols, or a PLT.

#### Attaching the Import Table to a PIE Plan

The current ordinary executable-import helper requires `format_elf_exec`.

#### Continuing with the Original Plan

After calling `format_elfexe_tables`, use the returned plan for the remaining
lifecycle.

#### Calling the External Name Directly

Call the local PLT label declared by the import entry.

#### Giving Generated Metadata RWX Permissions

The ordinary facade separates executable PLT bytes from writable GOT and
dynamic state. Do not combine them into a manually created writable and
executable segment.

#### Ignoring the Imported Function ABI

ELF symbol resolution does not validate arguments, register preservation, or
stack alignment.

#### Assuming Every Linux System Uses the Same Interpreter

Confirm that the target system provides the interpreter path recorded by the
generated file.

### Practical PIE and Dynamic-Import Rules

1. Use `format_elf64(format_elf_pie, segments)` for a direct-syscall PIE.
2. Keep PIE code and internal data references PC-relative.
3. Do not store absolute label values unless a runtime relocation will fix them.
4. Use `format_elf64(format_elf_exec, segments)` for the current import workflow.
5. Declare imported procedures with `format_elfexe_import_plt`.
6. Attach the import list with `format_elfexe_tables`.
7. Continue the lifecycle with the updated plan.
8. Call the generated local PLT label.
9. Follow the imported function's platform ABI.
10. Let the facade generate and separate PLT, GOT, interpreter, and dynamic data.
11. Treat PIE and dynamic imports as separate supported workflows for now.

Chapter 12 moves from runtime-loaded images to ELF32 and ELF64 object files,
where linkers consume named sections, symbols, and REL or RELA relocations.

## 12. ELF32 and ELF64 Object Files

An ELF object is a relocatable input for a linker. It is not loaded directly
as a process image.

The object records:

- named sections containing code, initialized data, or reserved storage;
- public symbols defined by this object;
- external symbols expected from other objects or libraries;
- relocation requests for encoded fields whose final values are not yet known.

The linker combines those facts into an executable or shared object. The
ordinary facade keeps section indexes, symbol indexes, table offsets, and
section-header counts internal.

### Create an ELF Object Plan

Use `format_elfobj32` for i386 objects and `format_elfobj64` for x86-64
objects:

```text
const object0: map = format_elfobj64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        )
    )
)
```

Descriptor order becomes the order of the user sections in the object. The
facade also generates the relocation sections, symbol table, string tables,
section-name table, and stack-permission note required by the ordinary
workflow.

Begin the object and write each declared section:

```text
format_begin(object0)
format_section_begin(object0, ".text")
...
format_section_end(object0, ".text")
```

An ELF object has no image base, program headers, subsystem, or executable
entry field. A symbol such as `_start` is only a public definition until the
linker selects it as the entry of a final executable.

### Sections Describe Linker Inputs

The ordinary object facade accepts:

- `format_code` for executable section contents;
- `format_data` for initialized bytes;
- `format_uninitialized_data` for BSS-style storage.

A BSS section becomes `SHT_NOBITS`. Its section header records the logical
size, but the object does not store the reserved bytes.

This permits a BSS section and the following file-backed section to have the
same file offset. The sections remain distinct because one consumes memory
size while the other consumes file bytes.

Keep each section's start label. Public symbols and relocations use it to
derive section-relative values:

```text
format_section_begin(object0, ".bss")
bss_start:
scratch:
    reserve(64)
format_section_end(object0, ".bss")
```

### Public Symbols Describe Definitions

Declare a definition with `format_elfobj_public`:

```text
format_elfobj_public(
    "scratch",
    ".bss",
    bss_start,
    scratch,
    64,
    elfobj_stt_object
)
```

The arguments identify:

1. the link-visible symbol name;
2. the section containing the definition;
3. a label at the start of that section;
4. the symbol label;
5. the symbol size;
6. the ELF symbol type.

The facade calculates the section index and section-relative symbol value.

Use:

- `elfobj_stt_func` for callable code;
- `elfobj_stt_object` for data or reserved storage;
- `elfobj_stt_notype` when no more specific type applies.

### External Symbols Describe Requirements

Declare an undefined symbol with `format_elfobj_extern`:

```text
format_elfobj_extern("helper", elfobj_stt_func)
```

The generated symbol has `SHN_UNDEF` as its section index. A linker must find
a matching definition in another input or library.

Symbol names are resolved by exact string equality. Use the spelling required
by the target ABI and the other objects in the link.

### Relocations Describe Encoded Patch Fields

An external relative call contains a four-byte displacement whose final value
depends on the linked address of the target.

Emit the opcode, reserve the displacement, and label the field itself:

```text
db(0xe8)
helper_disp:
dd(0)
```

Then declare the relocation:

```text
format_elfobj_reloc(
    ".text",
    text_start,
    helper_disp,
    "helper",
    elf_r_x86_64_plt32,
    0xfffffffffffffffc
)
```

The arguments identify:

1. the section containing the field;
2. the start of that section;
3. the address of the encoded field;
4. the target symbol name;
5. the architecture-specific relocation type;
6. the relocation addend.

The facade derives the relocation's section-relative offset and resolves the
target symbol index by name.

The `-4` addend accounts for the four-byte displacement field:

| Object kind | Relative call type | Addend encoding |
| --- | --- | --- |
| ELF32 | `elf_r_386_pc32` | `0xfffffffc` |
| ELF64 | `elf_r_x86_64_plt32` | `0xfffffffffffffffc` |

Choose relocation types from the target architecture's ABI. A relocation type
is not interchangeable merely because two fields have the same width.

### REL and RELA Store Addends Differently

The ordinary ELF32 workflow emits `SHT_REL` relocation sections. REL stores
the addend in the encoded field, so the facade writes the declared addend into
the four-byte placeholder during finalization.

The ordinary ELF64 workflow emits `SHT_RELA` relocation sections. RELA stores
the addend in the relocation row, while the encoded field remains a
placeholder for the linker.

This difference is internal to the generated tables. Both workflows use the
same `format_elfobj_reloc` declaration shape.

### Attach Symbols and Relocations

Collect declarations in lists:

```text
const symbols: list = list.of(...)
const relocs: list = list.of(...)
```

Attach them to the plan:

```text
const object: map = format_elfobj_tables(object0, symbols, relocs)
format_finish(object)
```

`format_elfobj_tables` returns an updated plan. Pass that returned value to
`format_finish`.

During finish, the facade:

1. groups relocations by target section;
2. resolves relocation targets by symbol name;
3. emits `REL` or `RELA` sections;
4. emits local section symbols;
5. emits the declared public and external symbols;
6. emits `.symtab`, `.strtab`, and `.shstrtab`;
7. emits a zero-sized non-executable stack note;
8. writes the final section-header table and ELF header counts.

### A Linkable ELF64 Object

This object defines `_start`, initialized data, and 64 bytes of BSS storage. It
calls an external function named `helper`:

```asm
import("format/format.inc");

const object0: map = format_elfobj64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        )
    )
)

format_begin(object0);

format_section_begin(object0, ".text");
text_start:
_start:
    db(0xe8);
helper_disp:
    dd(0);
    mov edi, eax
    mov eax, 60
    syscall
_start_end:
format_section_end(object0, ".text");

format_section_begin(object0, ".bss");
bss_start:
scratch:
    reserve(64);
format_section_end(object0, ".bss");

format_section_begin(object0, ".data");
data_start:
marker:
    dq(0x1122334455667788);
format_section_end(object0, ".data");

const symbols: list = list.of(
    format_elfobj_public(
        "_start",
        ".text",
        text_start,
        _start,
        _start_end - _start,
        elfobj_stt_func
    ),
    format_elfobj_public(
        "marker",
        ".data",
        data_start,
        marker,
        8,
        elfobj_stt_object
    ),
    format_elfobj_public(
        "scratch",
        ".bss",
        bss_start,
        scratch,
        64,
        elfobj_stt_object
    ),
    format_elfobj_extern("helper", elfobj_stt_func)
)

const relocs: list = list.of(
    format_elfobj_reloc(
        ".text",
        text_start,
        helper_disp,
        "helper",
        elf_r_x86_64_plt32,
        0xfffffffffffffffc
    )
)

const object: map = format_elfobj_tables(object0, symbols, relocs)
format_finish(object);
```

Another object can provide `helper` and use the exported BSS symbol:

```c
extern volatile unsigned char scratch[64];

int helper(void) {
    scratch[63] = 0x5a;
    return scratch[63] == 0x5a ? 0 : 1;
}
```

After linking, `_start` calls `helper` and exits with its return value. The
provider writes and reads the final byte of `scratch`, proving that the linker
allocated the complete 64-byte BSS definition.

The object stores no 64-byte BSS payload. Its `.bss` section has type
`SHT_NOBITS`, size 64, and writeable allocation flags.

### ELF32 Uses the Same Plan Model

The 32-bit source changes the plan constructor, instruction sequence, and
relocation type:

```asm
import("format/format.inc");

const object0: map = format_elfobj32(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        )
    )
)

format_begin(object0);

format_section_begin(object0, ".text");
text_start:
_start:
    db(0xe8);
helper_disp:
    dd(0);
    mov ebx, eax
    mov eax, 1
    db(0xcd, 0x80);
_start_end:
format_section_end(object0, ".text");

format_section_begin(object0, ".data");
data_start:
marker:
    dd(0x11223344);
format_section_end(object0, ".data");

format_section_begin(object0, ".bss");
bss_start:
scratch:
    reserve(64);
format_section_end(object0, ".bss");

const symbols: list = list.of(
    format_elfobj_public(
        "_start",
        ".text",
        text_start,
        _start,
        _start_end - _start,
        elfobj_stt_func
    ),
    format_elfobj_public(
        "marker",
        ".data",
        data_start,
        marker,
        4,
        elfobj_stt_object
    ),
    format_elfobj_public(
        "scratch",
        ".bss",
        bss_start,
        scratch,
        64,
        elfobj_stt_object
    ),
    format_elfobj_extern("helper", elfobj_stt_func)
)

const relocs: list = list.of(
    format_elfobj_reloc(
        ".text",
        text_start,
        helper_disp,
        "helper",
        elf_r_386_pc32,
        0xfffffffc
    )
)

const object: map = format_elfobj_tables(object0, symbols, relocs)
format_finish(object);
```

The same C definition can provide `helper` for a 32-bit link when compiled for
the matching target.

The ELF32 relocation section is `.rel.text`; the ELF64 relocation section is
`.rela.text`. The symbol names and section relationships remain the same.

### Generated Stack Permission

The ordinary facade adds a zero-sized `.note.GNU-stack` section with no
executable flag.

This tells compatible linkers that the object does not request an executable
process stack. It is generated metadata, not a user section descriptor, and it
does not add payload bytes.

Code requiring an executable stack is outside the ordinary facade's safety
model and requires an advanced object workflow.

### Common ELF Object Mistakes

#### Calling `format_entry`

Object files publish symbols. They do not contain an executable entry field.

#### Passing a Section Index

Pass the declared section name and its start label. The facade derives the
numeric section index.

#### Passing a Symbol Index

Pass the target symbol name. The facade resolves its generated symbol-table
index.

#### Relocating the Opcode Instead of the Field

For a relative call, label the four-byte displacement after the opcode.

#### Using the Wrong Relocation Type

Relocation types are architecture- and field-specific. Match the encoded
instruction and target ABI.

#### Omitting the PC-Relative Addend

The ordinary relative-call examples use `-4` because the displacement is
measured from the end of its four-byte field.

#### Treating BSS as File Data

Reserve the storage in a `format_uninitialized_data` section. Do not emit
initialized bytes into it.

#### Continuing with the Original Plan

Use the map returned by `format_elfobj_tables` when calling `format_finish`.

#### Expecting the Assembler to Select a Runtime Entry

The linker or link driver selects the final executable entry symbol.

#### Mixing ELF32 and ELF64 Inputs

All objects in one link must use compatible machine, class, ABI, and calling
conventions.

### Practical ELF Object Rules

1. Use `format_elfobj32` or `format_elfobj64` for the target object class.
2. Declare every user section before calling `format_begin`.
3. Keep a start label for each section used by symbols or relocations.
4. Use `format_uninitialized_data` and `reserve` for BSS.
5. Describe definitions with `format_elfobj_public`.
6. Describe unresolved requirements with `format_elfobj_extern`.
7. Label the exact encoded field that the linker must patch.
8. Choose the relocation type from the target ABI.
9. Pass the two's-complement `-4` addend for the shown relative calls.
10. Attach symbols and relocations with `format_elfobj_tables`.
11. Finish with the returned plan.
12. Let the facade generate section indexes, symbol indexes, tables, and the
    non-executable stack note.
13. Link only with objects that use a compatible architecture and ABI.

Chapter 13 builds ELF64 shared objects, where exported and imported dynamic
symbols are resolved by the runtime loader rather than a static link alone.

## 13. ELF64 Shared Objects

An ELF shared object is an `ET_DYN` image designed to be loaded into another
process. It normally has no process entry point of its own. Instead, it
publishes dynamic symbols that a program or another shared object can resolve
at runtime.

The ordinary ELF64 shared-object facade can:

- publish functions or data through the dynamic symbol table;
- import procedures from named shared libraries through generated PLT and GOT
  state;
- describe multiple user LOAD segments with independent permissions;
- represent reserve-only BSS without storing zero-filled payload bytes;
- generate the SONAME, dynamic tables, hash table, relocations, section
  headers, and program headers required by the runtime loader.

This chapter builds one shared object that imports `puts`, exports a callable
function, uses BSS state, and can be loaded through `dlopen`.

### Create the Shared-Object Plan

Create an ordinary ELF64 shared-object plan with:

```text
format_elf64_so(soname, segments)
```

The SONAME is the library identity recorded in the dynamic table:

```asm
const image0: map = format_elf64_so(
    "libxirasm_ch13.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
```

Descriptor order determines the order of the user LOAD entries and user
section headers. Use the same permission model as an executable:

- code is readable and executable;
- BSS and initialized mutable data are readable and writeable;
- constants are readable;
- no user segment should be both writeable and executable.

The ordinary shared-object workflow currently supports ELF64 only.

### Declare Exported Symbols

Declare an exported symbol with:

```text
format_elfso_export(target_label, export_name, segment_name, symbol_size)
```

The arguments identify:

1. the label defined by the source;
2. the name published in the dynamic symbol table;
3. the declared user segment containing the symbol;
4. the symbol size recorded for runtime tools and consumers.

For example:

```asm
const exports: list = list.of(
    format_elfso_export(
        "xirasm_call_puts",
        "xirasm_call_puts",
        ".text",
        46
    )
)
```

The target and published names may differ. The segment name must match a
descriptor in the plan, and the size must be nonzero.

The current ordinary facade requires at least one export. It resolves the
target label and generated section index during finalization; users do not
calculate dynamic-symbol rows or section indexes.

### Declare PLT Imports

Declare an imported procedure with:

```text
format_elfso_import_plt(library, name, slot_label, plt_label)
```

For example:

```asm
const imports: list = list.of(
    format_elfso_import_plt(
        "libc.so.6",
        "puts",
        "puts_gotplt",
        "puts_plt"
    )
)
```

The library name becomes a `DT_NEEDED` entry. The external symbol name becomes
an undefined dynamic symbol. The two local labels name the generated GOT/PLT
slot and PLT entry.

Ordinary calls use the PLT label:

```text
call puts_plt
```

The runtime loader resolves `puts` and writes its address into the generated
GOT/PLT slot.

### Attach Dynamic Tables Before Beginning the Image

Attach both declaration lists with:

```text
format_elfso_tables(plan, exports, imports)
```

Use the returned plan for the complete lifecycle:

```asm
const image: map = format_elfso_tables(image0, exports, imports)
format_begin(image);
```

The tables must be attached before `format_begin`. Imports affect the generated
program-header count and require separate executable PLT and writeable metadata
mappings.

An export-only shared object passes an empty import list:

```text
format_elfso_tables(image0, exports, list.new())
```

### A Multi-Segment Shared Object

The following source imports `puts`, exports `xirasm_call_puts`, stores its call
count in BSS, and keeps text, constants, BSS, initialized data, generated PLT,
and generated dynamic metadata in appropriately permitted mappings:

```asm
import("format/format.inc");

const image0: map = format_elf64_so(
    "libxirasm_ch13.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
const exports: list = list.of(
    format_elfso_export(
        "xirasm_call_puts",
        "xirasm_call_puts",
        ".text",
        46
    )
)
const imports: list = list.of(
    format_elfso_import_plt("libc.so.6", "puts", "puts_gotplt", "puts_plt")
)
const image: map = format_elfso_tables(image0, exports, imports)
format_begin(image);

format_segment_begin(image, ".text");
xirasm_call_puts:
    mov rax, [rel call_count]
    add rax, 1
    mov [rel call_count], rax
    lea rdi, [rel message_text]
    sub rsp, 8
    call puts_plt
    add rsp, 8
    mov rax, [rel call_count]
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".bss");
call_count:
    reserve(64);
format_segment_end(image, ".bss");

format_segment_begin(image, ".rodata");
message_text:
    db("XIRASM shared object", 0);
format_segment_end(image, ".rodata");

format_segment_begin(image, ".data");
library_state:
    dq(0x1122334455667788);
format_segment_end(image, ".data");

format_finish(image);
```

The function follows the x86-64 System V calling convention. It preserves the
required stack alignment before calling `puts`, uses RIP-relative references
for internal data, and returns the updated call count in `rax`.

The shared object has no executable entry point. `format_finish` emits the
runtime metadata after the user segments and finalizes all generated addresses,
sizes, indexes, and counts.

### Load and Call the Export

A C host can load the file and resolve the exported function:

```c
#include <dlfcn.h>

typedef long (*entry_fn)(void);

int main(void) {
    void *handle = dlopen("./libxirasm_ch13.so", RTLD_NOW);
    if (handle == 0) {
        return 1;
    }

    entry_fn entry = (entry_fn)dlsym(handle, "xirasm_call_puts");
    if (entry == 0) {
        dlclose(handle);
        return 2;
    }

    const long first = entry();
    const long second = entry();
    dlclose(handle);
    return first == 1 && second == 2 ? 0 : 3;
}
```

The first call prints the message and returns 1. The second call proves that
the BSS state remains allocated in the loaded image and returns 2.

`dlsym` identifies the function by its published export name. It does not use a
source label, section name, or numeric symbol index.

### BSS Is Memory Without File Payload

The `.bss` segment contains only:

```asm
reserve(64);
```

Its program header has file size zero and memory size 64. Its section header
uses `SHT_NOBITS` with size 64. The following `.rodata` segment may begin at the
same compact file offset because BSS consumes virtual memory, not file bytes.

The loader maps the BSS on its own writeable virtual page and initializes the
memory to zero.

Keep an ordinary BSS segment reserve-only. If initialized bytes and reserved
storage must share one logical area, use separate ordinary segments or a
specialized advanced layout.

### Generated Runtime Metadata

For this import-and-export workflow, the facade generates:

- `.dynsym` and `.dynstr` for imported and exported names;
- a System V ELF hash table;
- a `.plt` section and GOT/PLT state for imported procedures;
- `R_X86_64_JUMP_SLOT` relocations;
- a `.dynamic` section containing `DT_SONAME`, `DT_NEEDED`, and table links;
- a section-name string table and final section-header table;
- LOAD and DYNAMIC program headers.

Users supply names, permissions, labels, and symbol sizes. The facade derives
program-header rows, section indexes, symbol indexes, string offsets,
relocation rows, file offsets, virtual addresses, and table sizes.

### Executable and Writeable State Remain Separate

When imports are present, generated state is mapped in two additional LOAD
entries:

- the PLT is readable and executable;
- GOT, symbols, strings, relocations, dynamic data, and section metadata are
  readable and writeable.

No LOAD is simultaneously writeable and executable.

The physical file remains compact. Separate virtual pages enforce permissions
without filling the file with page-sized zero gaps, and every LOAD preserves
the ELF page-congruence rule between its file offset and virtual address.

### Shared Objects Must Follow the Consumer ABI

Dynamic symbol resolution does not define a function's calling convention.
Every exported and imported procedure must follow the ABI expected by its
caller or callee.

For an x86-64 System V function:

- receive arguments in the required registers;
- preserve callee-saved registers;
- maintain stack alignment before calls;
- return values in the expected registers;
- use compatible data sizes and structures.

The same rule applies to imported functions. A correct PLT relocation cannot
repair an incorrect call sequence.

### Current Ordinary-Layer Boundary

The ordinary shared-object facade currently provides:

- ELF64 shared objects;
- at least one exported dynamic symbol;
- optional PLT-based function imports;
- multiple user LOAD segments;
- reserve-only BSS;
- generated SONAME, hash, symbol, string, relocation, PLT, GOT, dynamic, and
  section-header state.

It does not currently provide an ordinary ELF32 shared-object constructor,
symbol-version tables, TLS, constructor arrays, GNU hash, or arbitrary custom
dynamic tags.

Do not mix width-specific compatibility wrappers or direct row-oriented helpers
into an ordinary plan to bypass these boundaries. Specialized layouts belong
in the separate advanced format guide.

### Common Shared-Object Mistakes

#### Calling `format_entry`

A shared object publishes dynamic symbols. It does not use an executable entry
point in the ordinary workflow.

#### Omitting Every Export

The current ordinary facade requires at least one export.

#### Attaching Tables After `format_begin`

Imports change the generated program-header layout. Attach exports and imports
before beginning the image.

#### Calling the External Name Directly

Call the local PLT label supplied by `format_elfso_import_plt`.

#### Using the Wrong Export Segment

The declared export segment must be the user segment containing the target
label.

#### Recording an Incorrect Symbol Size

Keep the export size synchronized with the emitted function or object.

#### Emitting Bytes into BSS

A reserve-only BSS segment becomes `SHT_NOBITS`. Put initialized bytes in a
file-backed segment.

#### Giving One Segment Write and Execute Permissions

Keep code and mutable state separate. The ordinary facade already separates
generated PLT bytes from generated writeable metadata.

#### Ignoring the Platform ABI

Both sides of a dynamic call must agree on registers, stack alignment, data
layout, and return values.

#### Expecting SONAME to Locate the File

SONAME identifies the library after it is found. Search paths, loader
configuration, and the caller still determine how the file is located.

### Practical ELF64 Shared-Object Rules

1. Create the plan with `format_elf64_so`.
2. Give the file a nonempty SONAME.
3. Declare user segments with the minimum required permissions.
4. Keep reserve-only BSS in its own writeable segment.
5. Declare every published symbol with `format_elfso_export`.
6. Declare imported procedures with `format_elfso_import_plt`.
7. Attach exports and imports with `format_elfso_tables` before `format_begin`.
8. Use the returned plan for every lifecycle call.
9. Call imported procedures through their generated local PLT labels.
10. Follow the platform ABI for every imported and exported procedure.
11. Let the facade derive dynamic tables, indexes, offsets, and program headers.
12. Keep executable and writeable mappings separate.
13. Load and resolve exported names through the target platform's dynamic-loader
    API.

This completes the ordinary executable-format guide. It has covered PE
executables and DLLs, COFF objects, ELF executables and PIE, ELF objects, and
ELF64 shared objects through the user-facing `format.inc` facade.

Direct format includes, compatibility wrappers, explicit table rows, and
specialized metadata construction are advanced interfaces. They are
documented separately rather than being mixed into the ordinary workflow.
