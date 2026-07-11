field:
emit.u8(0)

defer {
    const data: bytes = fs.read_bytes("../13-files-data/banner.txt")
    store.u8(field, len(data))
}
