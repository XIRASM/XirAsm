// Win32 GUID memory-layout helper.
//
// data4 is the fourth 16-bit textual group. data5 is the final 48-bit group.

fn win32_guid(data1: u64, data2: u64, data3: u64, data4: u64, data5: u64) -> bytes {
    assert(data1 <= 0xffffffff, "GUID data1 exceeds 32 bits");
    assert(data2 <= 0xffff, "GUID data2 exceeds 16 bits");
    assert(data3 <= 0xffff, "GUID data3 exceeds 16 bits");
    assert(data4 <= 0xffff, "GUID data4 exceeds 16 bits");
    assert(data5 <= 0xffffffffffff, "GUID data5 exceeds 48 bits");

    let result: bytes = bytes.le(data1, 4)
    result = bytes.concat(result, bytes.le(data2, 2))
    result = bytes.concat(result, bytes.le(data3, 2))
    result = bytes.push(result, (data4 >> 8) & 0xff)
    result = bytes.push(result, data4 & 0xff)
    result = bytes.push(result, (data5 >> 40) & 0xff)
    result = bytes.push(result, (data5 >> 32) & 0xff)
    result = bytes.push(result, (data5 >> 24) & 0xff)
    result = bytes.push(result, (data5 >> 16) & 0xff)
    result = bytes.push(result, (data5 >> 8) & 0xff)
    result = bytes.push(result, data5 & 0xff)
    return result;
}
