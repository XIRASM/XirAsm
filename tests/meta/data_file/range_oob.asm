// offset 2 plus count 8 exceeds blob.bin length.
emit.bytes(fs.read_bytes("blob.bin", 2, 8));
