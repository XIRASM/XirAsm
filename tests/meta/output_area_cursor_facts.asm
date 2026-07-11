emit.u8(0xaa);
assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 1);
assert(tail_reserve_size() == 0);

reserve(3);
assert(file_cursor_real() == 1);
assert(file_cursor_potential() == 4);
assert(tail_reserve_size() == 3);

emit.u8(0xbb);
assert(file_cursor_real() == 5);
assert(file_cursor_potential() == 5);
assert(tail_reserve_size() == 0);
