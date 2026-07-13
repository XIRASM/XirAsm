import fs from "fs";

const source = fs.readFileSync("src/languageData.ts", "utf8");
const requiredLabels = [
  "import",
  "include",
  "fn",
  "break",
  "continue",
  "defer",
  "struct",
  "emit.u8",
  "emit.bytes",
  "db",
  "rb",
  "store.u32",
  "load.u32",
  "region.begin",
  "region.end",
  "x86.use64",
  "riscv.use64",
  "pe_begin64",
  "pe_finalize_section64",
  "pe_import_emit64",
  "coff_begin64",
  "elfexe_begin64",
  "elfso_begin64",
  "OpMemoryModel",
];
const missing = requiredLabels.filter((label) => !source.includes(JSON.stringify(label)));
if (missing.length > 0) throw new Error(`language data is missing entries: ${missing.join(", ")}`);
for (const banned of [["include", "_once"].join(""), ["end", " macro"].join(""), ["rv", "_raw"].join(""), ["was", "m_"].join(""), ["end", " struc"].join(""), ["Z", "ASMG"].join("")]) {
  if (source.includes(banned)) throw new Error(`language data contains stale token: ${banned}`);
}
console.log(`language data ok (${requiredLabels.length} sentinel entries)`);
