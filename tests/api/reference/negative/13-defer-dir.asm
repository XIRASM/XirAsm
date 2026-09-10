// Directory listing is unavailable in a deferred finalizer: the value phase runs
// after layout, and the resolver refuses file access there instead of returning a
// listing the finalizer could not act on.
defer {
    const names: list = fs.list_dir("../13-files-data/listing")
    assert(len(names) == 3);
}
