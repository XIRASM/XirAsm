// fs.read_bytes range uses 0-based file offset plus byte count.
emit.bytes(fs.read_bytes("blob.bin", 1, 2));
emit.bytes(fs.read_bytes("blob.bin"));
