// Tail reserve advances logical region size but is not materialized in flat
// file bytes. A following initialized byte makes the reserve a middle gap.
// This is the custom-format boundary for section-tail reserve trimming.

region.begin("payload", 0x5000, 0);

header:
emit.bytes(b"HDR0");
logical_size_field:
emit.u32(0);
middle_size_field:
emit.u32(0);
tail_file_size_field:
emit.u32(0);
tail_logical_size_field:
emit.u32(0);

middle_start:
emit.u8(0xaa);
reserve(3);
middle_after_gap:
emit.u8(0xee);
tail_start:
reserve(0x20);
tail_end:

defer {
    store.u32(logical_size_field, tail_end - header);
    store.u32(middle_size_field, middle_after_gap - middle_start);
    store.u32(tail_file_size_field, region_file_size(header));
    store.u32(tail_logical_size_field, region_logical_size(header));

    assert(load.u32(logical_size_field) == tail_end - header);
    assert(load.u32(middle_size_field) == 4);
    assert(load.u32(tail_file_size_field) == tail_start - header);
    assert(load.u32(tail_logical_size_field) == tail_end - header);
    assert(region_file_offset(header) == 0);
}
