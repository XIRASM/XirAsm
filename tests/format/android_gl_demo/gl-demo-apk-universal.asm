// The renderer for both supported device ABIs inside one archive, which is what a
// build has to ship so that a phone installs the AArch64 library and an emulator
// installs the x86-64 one from the same package.
//
// Both variants carry the same SONAME and the same exported entry point; only the
// instruction set and the import mechanism differ (GOT slots with
// R_AARCH64_GLOB_DAT against a PLT with R_X86_64_JUMP_SLOT).
//
// Assemble the two libraries first, then this file:
//   xirasm gl-demo-so.asm -o libmain-x86_64.so
//   xirasm gl-demo-so-aarch64.asm -o libmain-aarch64.so
//   xirasm gl-demo-apk-universal.asm -o demo-universal-unsigned.apk
//   zipalign -f -P 16 4 demo-universal-unsigned.apk demo-universal-aligned.apk
//   apksigner sign --ks <keystore> --out demo-universal.apk demo-universal-aligned.apk
import("format/apk.inc");

origin(0);

let app: map = apk_new("com.example.xirasm.gldemo", 1, "1.0", "main")
app = apk_set_sdk(app, 26, 34)
app = apk_res_dir_at(app, "res", "res")
app = apk_skip_dex(app)
app = apk_native_lib(app, "arm64-v8a", "libmain.so", "libmain-aarch64.so")
app = apk_native_lib(app, "x86_64", "libmain.so", "libmain-x86_64.so")
apk_emit(app);
