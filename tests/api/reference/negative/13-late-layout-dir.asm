// Directory listing is unavailable in a late-layout block: the phase allows only
// the layout operations it can still perform, so the call is refused outright
// rather than answered from a stale listing.
late_layout {
    const names: list = fs.list_dir("../13-files-data/listing")
    assert(len(names) == 3);
}
