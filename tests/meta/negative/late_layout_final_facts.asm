// Final region facts are finalizer-only. Late layout still runs before the
// image is sealed, so asking for a final size there must be refused at the line
// that asked, and the message must say which phase the query belongs to.
emit.u8(0x10)

late_layout {
    print(region_file_size(0))
}
