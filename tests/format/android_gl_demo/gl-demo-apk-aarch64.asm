// The same archive as gl-demo-apk.asm, carrying the AArch64 renderer instead of
// the x86-64 one. The package name is the same on purpose: installing this build
// replaces the x86-64 one, so whatever runs afterwards is the AArch64 library.
//
// Assemble the library first, then this file:
//   xirasm gl-demo-so-aarch64.asm -o libmain.so
//   xirasm gl-demo-apk-aarch64.asm -o demo-unsigned.apk
//   zipalign -f -P 16 4 demo-unsigned.apk demo-aligned.apk
//   apksigner sign --ks <keystore> --out demo.apk demo-aligned.apk
import("format/apk.inc");

origin(0);

let app: map = apk_new("com.example.xirasm.gldemo", 1, "1.0", "main")
app = apk_set_sdk(app, 26, 34)
app = apk_res_dir_at(app, "res", "res")
app = apk_skip_dex(app)
app = apk_native_lib(app, "arm64-v8a", "libmain.so", "libmain.so")
apk_emit(app);
