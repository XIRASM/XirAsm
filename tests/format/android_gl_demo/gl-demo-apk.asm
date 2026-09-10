// The APK around the renderer library: everything in this archive is written by
// the assembler, and there is no runtime beyond the platform's own libraries.
//
// Assemble the library first, then this file:
//   xirasm gl-demo-so.asm -o libmain.so
//   xirasm gl-demo-apk.asm -o demo-unsigned.apk
//   zipalign -f -P 16 4 demo-unsigned.apk demo-aligned.apk
//   apksigner sign --ks <keystore> --out demo.apk demo-aligned.apk
//
// The resource tree beside this file declares the launcher icon and the Chinese
// application name, and the scanner in format/apk.inc binds both.
import("format/apk.inc");

origin(0);

let app: map = apk_new("com.example.xirasm.gldemo", 1, "1.0", "main")
app = apk_set_sdk(app, 26, 34)
app = apk_res_dir_at(app, "res", "res")
app = apk_skip_dex(app)
app = apk_native_lib(app, "x86_64", "libmain.so", "libmain.so")
apk_emit(app);
