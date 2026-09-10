// api-matrix-fixture: fs.list_dir(
// api-matrix-fixture: fs.is_dir(

// Directory listing through the controlled resolver. Entries come back sorted by
// byte value, so the fixture asserts exact positions; the names are chosen so that
// byte order differs from the case-insensitive order a filesystem may already
// return. A directory is listed like any other entry: the name alone does not say
// whether it can be entered, which is why fs.is_dir asks separately.
const entries: list = fs.list_dir("listing")
assert(len(entries) == 5);
assert(list.get(entries, 0) == "Zebra.txt");
assert(list.get(entries, 1) == "_under.txt");
assert(list.get(entries, 2) == "alpha.txt");
assert(list.get(entries, 3) == "beta.txt");
assert(list.get(entries, 4) == "sub");

assert(fs.is_dir("listing"));
assert(fs.is_dir("listing/sub"));
assert(!fs.is_dir("listing/alpha.txt"));
assert(!fs.is_dir("listing/missing.txt"));
assert(fs.exists("listing/sub/inner.txt"));

const nested: list = fs.list_dir("listing/sub")
assert(len(nested) == 1);
assert(list.get(nested, 0) == "inner.txt");

emit.u8(len(entries));
