// Non-ASCII string values through the arsc.inc facade. A UTF-8 pool entry
// stores the UTF-16 code unit count and the UTF-8 byte count separately, and
// the two differ as soon as a value leaves ASCII: the first line below is 13
// code units in 23 bytes, and the second line exercises a four-byte character,
// which becomes a surrogate pair and counts as two code units. The expected
// bytes match an aapt2 linked table for the same resources.
//
// XIRASM sources are ASCII, so the text comes from a data file. That is the
// documented path for non-ASCII content, and it keeps the assembly listing and
// the diagnostics readable.
import("../../include/format/arsc.inc");

const raw: string = fs.read_text("apk_zh_strings.txt")
const values: list = split(raw, "|")
assert(len(values) == 2, "arsc non-ASCII fixture data must hold two values");

let tbl: map = arsc_new("probe.zh", 0x7f)
tbl = arsc_string(tbl, "app_name", trim(list.get(values, 0)));
tbl = arsc_string(tbl, "emoji_name", trim(list.get(values, 1)));
tbl = arsc_string(tbl, "ascii_name", "Plain ASCII")

let blob = bytes.new()
arsc_build(blob, tbl);
assert(len(blob) == 704, "arsc non-ASCII fixture size drifted");
emit.bytes(blob);
