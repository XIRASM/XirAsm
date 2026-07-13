import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const extensionRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(extensionRoot, "..", "..");
const matrixPath = path.join(repoRoot, "tests", "api", "user-api-matrix.tsv");
const formatRoot = path.join(repoRoot, "include", "format");
const riscvTablePath = path.join(repoRoot, "deps", "xirasm-lib", "src", "riscv_encoder", "generated_core.zig");
const outputPath = path.join(extensionRoot, "src", "languageData.ts");

const items = new Map();
function add(label, detail, documentation, kind = "Function") {
  if (!label || items.has(label)) return;
  items.set(label, { label, detail, documentation, kind });
}

for (const keyword of ["fn", "const", "let", "var", "return", "if", "else", "while", "for", "in", "break", "continue", "defer", "struct", "packed", "union", "enum", "match", "is"]) {
  add(keyword, "Meta language keyword", `XIRASM compile-time Meta keyword: \`${keyword}\`.`, "Keyword");
}
for (const typeName of ["void", "bool", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "usize", "string", "bytes", "list", "map"]) {
  add(typeName, "Meta type", `XIRASM Meta type \`${typeName}\`.`, "TypeParameter");
}
for (const constant of ["true", "false", "null", "target.isa", "target.bits"]) {
  add(constant, "Meta constant", `XIRASM compile-time value \`${constant}\`.`, "Constant");
}

for (const builtin of [
  ["region.end", "XIRASM api", "End the current logical output region."],
  ["virtual.end", "XIRASM api", "End the current virtual output region."],
  ["label.define", "XIRASM api", "Define a label from a computed name."],
  ["label.alias", "XIRASM api", "Create a label alias from a computed name."],
]) {
  add(builtin[0], builtin[1], builtin[2], "Function");
}

if (fs.existsSync(matrixPath)) {
  const lines = fs.readFileSync(matrixPath, "utf8").trimEnd().split(/\r?\n/);
  const headers = lines.shift()?.split("\t") ?? [];
  const idx = Object.fromEntries(headers.map((name, index) => [name, index]));
  for (const line of lines) {
    const cols = line.split("\t");
    const category = cols[idx.category] ?? "api";
    const surface = cols[idx.surface] ?? "";
    const note = cols[idx.note] ?? "";
    if (!surface || surface.includes(" ") || surface === "ISA instruction" || surface === "label:") continue;
    const kind = category === "syntax" ? "Keyword" : "Function";
    add(surface, `XIRASM ${category}`, note || `XIRASM ${category} surface \`${surface}\`.`, kind);
  }
}

function walk(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.isFile() && entry.name.endsWith(".inc")) out.push(full);
  }
  return out;
}
for (const file of walk(formatRoot)) {
  const rel = path.relative(repoRoot, file).replaceAll(path.sep, "/");
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  let braceDepth = 0;
  lines.forEach((line, i) => {
    const atTopLevel = braceDepth === 0;
    let m = /^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:->\s*([A-Za-z0-9_]+))?/.exec(line);
    if (atTopLevel && m) {
      const signature = `fn ${m[1]}(${m[2]})${m[3] ? ` -> ${m[3]}` : ""}`;
      add(m[1], "Format DSL helper", `**${signature}**\n\nSource: \`${rel}:${i + 1}\`.`, "Function");
    }
    if (atTopLevel && !m) {
      m = /^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)\s*:/.exec(line);
      if (m) add(m[1], "Format DSL constant", `Format helper constant from \`${rel}:${i + 1}\`.`, "Constant");
    }
    for (const ch of line) {
      if (ch === "{") braceDepth += 1;
      else if (ch === "}" && braceDepth > 0) braceDepth -= 1;
    }
  });
}

if (fs.existsSync(riscvTablePath)) {
  const text = fs.readFileSync(riscvTablePath, "utf8");
  const re = /\.\{\s*\.name\s*=\s*"([^"]+)"/g;
  let match;
  while ((match = re.exec(text))) add(match[1], "RISC-V instruction", "RISC-V native ISA mnemonic accepted by the XIRASM backend.", "Keyword");
}
for (const spv of ["OpCapability", "OpMemoryModel", "OpEntryPoint", "OpExecutionMode", "OpName", "OpTypeVoid", "OpTypeInt", "OpTypeFloat", "OpTypePointer", "OpConstant", "OpFunction", "OpLabel", "OpReturn", "OpFunctionEnd"]) {
  add(spv, "SPIR-V instruction", "SPIR-V native source instruction parsed by the backend.", "Keyword");
}
for (const reg of ["al","cl","dl","bl","ah","ch","dh","bh","ax","cx","dx","bx","sp","bp","si","di","eax","ecx","edx","ebx","esp","ebp","esi","edi","rax","rcx","rdx","rbx","rsp","rbp","rsi","rdi","r8","r9","r10","r11","r12","r13","r14","r15","xmm0","xmm1","xmm2","xmm3","xmm4","xmm5","xmm6","xmm7","ymm0","ymm1","ymm2","ymm3","ymm4","ymm5","ymm6","ymm7","zmm0","zmm1","zmm2","zmm3","zmm4","zmm5","zmm6","zmm7","k0","k1","k2","k3","k4","k5","k6","k7"]) {
  add(reg, "x86 register", `x86 register \`${reg}\`.`, "Value");
}

const kindMap = {
  Function: "CompletionItemKind.Function",
  Keyword: "CompletionItemKind.Keyword",
  Constant: "CompletionItemKind.Constant",
  Value: "CompletionItemKind.Value",
  TypeParameter: "CompletionItemKind.TypeParameter",
};
const rows = [...items.values()].sort((a, b) => a.label.localeCompare(b.label));
const body = rows.map((entry) => `  item(${JSON.stringify(entry.label)}, ${JSON.stringify(entry.detail)}, ${JSON.stringify(entry.documentation)}, ${kindMap[entry.kind] ?? "CompletionItemKind.Function"}),`).join("\n");
const source = `import { CompletionItemKind } from "vscode-languageserver/node";\n\nexport type LanguageItem = {\n  label: string;\n  detail: string;\n  documentation: string;\n  kind: CompletionItemKind;\n};\n\nexport const allCompletionItems: LanguageItem[] = [\n${body}\n];\n\nexport const hoverByLabel = buildHoverMap(allCompletionItems);\n\nfunction buildHoverMap(items: LanguageItem[]): Map<string, LanguageItem> {\n  const result = new Map<string, LanguageItem>();\n  for (const entry of items) {\n    result.set(entry.label, entry);\n  }\n  return result;\n}\n\nfunction item(label: string, detail: string, documentation: string, kind: CompletionItemKind): LanguageItem {\n  return { label, detail, documentation, kind };\n}\n`;
fs.writeFileSync(outputPath, source, "utf8");
console.log(`generated ${path.relative(extensionRoot, outputPath)} (${rows.length} entries)`);
