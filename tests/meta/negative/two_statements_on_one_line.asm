// A line holds one statement. XIRASM parses line by line, so a second statement
// on the same line has to be reported as such: taking the last `)` on the line
// used to reach across it and blame the first call's arguments instead.
x86.use64();

emit.u8(0x11); emit.u8(0x22)
