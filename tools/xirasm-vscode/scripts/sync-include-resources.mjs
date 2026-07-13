import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const extensionRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(extensionRoot, "..", "..");
const source = path.join(repoRoot, "include");
const destination = path.join(extensionRoot, "resources", "include");

if (!fs.existsSync(source)) {
  throw new Error(`repository include tree not found: ${source}`);
}

fs.rmSync(destination, { recursive: true, force: true });
fs.mkdirSync(path.dirname(destination), { recursive: true });
copyTree(source, destination);

console.log(`synced include resources: ${path.relative(repoRoot, source)} -> ${path.relative(repoRoot, destination)}`);

function copyTree(sourceDir, destinationDir) {
  fs.mkdirSync(destinationDir, { recursive: true });
  for (const entry of fs.readdirSync(sourceDir, { withFileTypes: true })) {
    if (entry.name === "std" && entry.isDirectory()) continue; // 不把 stdlib 带入 LSP
    const sourcePath = path.join(sourceDir, entry.name);
    const destinationPath = path.join(destinationDir, entry.name);
    if (entry.isDirectory()) {
      copyTree(sourcePath, destinationPath);
    } else if (entry.isFile()) {
      copyFile(sourcePath, destinationPath);
    }
  }
}

function copyFile(sourcePath, destinationPath) {
  const ext = path.extname(sourcePath).toLowerCase();
  if (ext === ".inc" || ext === ".md") {
    let text = fs.readFileSync(sourcePath, "utf8").replace(/\r\n/g, "\n");
    if (text.length > 0) text = text.replace(/\n+$/, "\n");
    fs.writeFileSync(destinationPath, text, "utf8");
    return;
  }
  fs.copyFileSync(sourcePath, destinationPath);
}
