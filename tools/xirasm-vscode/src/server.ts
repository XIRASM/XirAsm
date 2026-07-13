import { spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { pathToFileURL } from "url";
import {
  CompletionItem,
  CompletionItemKind,
  CompletionParams,
  createConnection,
  Diagnostic,
  DidChangeConfigurationNotification,
  DocumentSymbol,
  Hover,
  InitializeParams,
  InitializeResult,
  Location,
  MarkupKind,
  ProposedFeatures,
  Range,
  TextDocumentPositionParams,
  TextDocuments,
  TextDocumentSyncKind,
  SymbolKind,
  WorkspaceSymbol,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";
import { analyzeDocument, includeAtPosition, includeSearchRoots, literalIncludes, wordAt } from "./analyzer";
import { allCompletionItems, hoverByLabel } from "./languageData";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
let workspaceRoots: string[] = [];
let extensionRoot: string | undefined;
let settings: ServerSettings = defaultSettings();
let hasConfigurationCapability = false;

type ServerSettings = {
  diagnostics: {
    assembler: {
      enabled: boolean;
      executablePath: string;
      timeoutMs: number;
    };
  };
};

connection.onInitialize((params: InitializeParams): InitializeResult => {
  hasConfigurationCapability = Boolean(params.capabilities.workspace?.configuration);
  workspaceRoots = (params.workspaceFolders ?? [])
    .map((folder) => uriToPath(folder.uri))
    .filter((value): value is string => value !== undefined);
  extensionRoot = typeof params.initializationOptions?.extensionRoot === "string"
    ? params.initializationOptions.extensionRoot
    : undefined;
  settings = normalizeSettings(params.initializationOptions?.settings);

  return {
    capabilities: {
      textDocumentSync: {
        openClose: true,
        change: TextDocumentSyncKind.Incremental,
        save: true,
      },
      completionProvider: {
        resolveProvider: true,
        triggerCharacters: [".", "_", "\"", "'", "/", "\\"],
      },
      hoverProvider: true,
      documentSymbolProvider: true,
      definitionProvider: true,
      referencesProvider: true,
      workspaceSymbolProvider: true,
    },
  };
});

connection.onInitialized(() => {
  if (hasConfigurationCapability) {
    connection.client.register(DidChangeConfigurationNotification.type, undefined).catch(() => {
      // Optional registration; older clients may reject it.
    });
  }
});

documents.onDidChangeContent((change) => validate(change.document, false));
documents.onDidOpen((event) => validate(event.document, false));
documents.onDidClose((event) => {
  connection.sendDiagnostics({ uri: event.document.uri, diagnostics: [] });
});

documents.onDidSave((event) => validate(event.document, true));

connection.onDidChangeConfiguration(async () => {
  if (hasConfigurationCapability) {
    const raw = await connection.workspace.getConfiguration("xirasm");
    settings = normalizeSettings(raw);
  }
  for (const document of documents.all()) validate(document, false);
});

connection.onCompletion((params: CompletionParams): CompletionItem[] => {
  const document = documents.get(params.textDocument.uri);
  if (document) {
    const includeItems = includePathCompletionItems(document, params.position);
    if (includeItems) return includeItems;
  }

  const items: CompletionItem[] = allCompletionItems.map((entry) => ({
    label: entry.label,
    kind: entry.kind,
    detail: entry.detail,
    documentation: {
      kind: MarkupKind.Markdown,
      value: entry.documentation,
    },
  }));

  if (document) items.push(...symbolCompletionItems(document));
  return items;
});

connection.onCompletionResolve((item) => item);

connection.onHover((params: TextDocumentPositionParams): Hover | null => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return null;
  const word = wordAt(document.getText(), params.position);
  const entry = hoverByLabel.get(word);
  if (entry) {
    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: `**${entry.label}**\n\n${entry.detail}\n\n${entry.documentation}`,
      },
    };
  }

  return symbolHover(document, word, params.position);
});

connection.onDocumentSymbol((params) => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return [];
  return analyzeDocument(document, analysisContext()).symbols;
});

connection.onDefinition((params: TextDocumentPositionParams): Location[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return [];
  const include = includeAtPosition(document, params.position, analysisContext());
  if (include?.resolvedPath) {
    return [{
      uri: pathToFileURL(include.resolvedPath).toString(),
      range: Range.create(0, 0, 0, 0),
    }];
  }

  const word = wordAt(document.getText(), params.position);
  if (!word) return [];
  return findDefinitionLocations(document, word, params.position);
});

connection.onReferences((params): Location[] => {
  const document = documents.get(params.textDocument.uri);
  if (!document) return [];
  const word = wordAt(document.getText(), params.position);
  if (!word) return [];
  if (word.startsWith(".")) return localReferenceLocations(document, word, params.position.line);
  return findReferenceLocations(document, word);
});

connection.onWorkspaceSymbol((params): WorkspaceSymbol[] => {
  const query = params.query.trim().toLowerCase();
  const result: WorkspaceSymbol[] = [];
  const seen = new Set<string>();

  for (const document of documents.all()) {
    addWorkspaceSymbols(result, seen, document.uri, document, query);
  }
  for (const filePath of workspaceSourceFiles()) {
    const document = readDiskDocument(filePath);
    if (!document) continue;
    addWorkspaceSymbols(result, seen, document.uri, document, query);
    if (result.length >= 500) break;
  }

  return result.slice(0, 500);
});

async function validate(document: TextDocument, runAssembler: boolean): Promise<void> {
  const analysis = analyzeDocument(document, analysisContext());
  const compilerDiagnostics = runAssembler ? await assembleDiagnostics(document) : [];
  connection.sendDiagnostics({ uri: document.uri, diagnostics: [...analysis.diagnostics, ...compilerDiagnostics] });
}

function analysisContext() {
  return {
    workspaceRoots: uniqueStrings([
      ...workspaceRoots,
      ...extensionIncludeRoots(),
    ]),
  };
}

function uriToPath(uri: string): string | undefined {
  if (!uri.startsWith("file://")) return undefined;
  try {
    const url = new URL(uri);
    return decodeURIComponent(url.pathname).replace(/^\/([A-Za-z]:)/, "$1");
  } catch {
    return undefined;
  }
}

function findDefinitionLocations(document: TextDocument, word: string, position: { line: number; character: number }): Location[] {
  if (word.startsWith(".")) {
    const scoped = scopedLocalSymbolLocation(document, word, position.line);
    if (scoped) return [scoped];
  }

  const direct = symbolLocations(document.uri, document, word);
  if (direct.length > 0) return direct;

  const result: Location[] = [];
  for (const includeDocument of includeChainDocuments(document)) {
    result.push(...symbolLocations(includeDocument.uri, includeDocument, word));
  }

  return result;
}

function scopedLocalSymbolLocation(document: TextDocument, word: string, referenceLine: number): Location | undefined {
  const lines = document.getText().split(/\r?\n/);
  const localDefinitions: Array<{ parent: string; location: Location }> = [];
  let parent = "";

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = stripAssemblerComment(lines[lineIndex] ?? "");
    const label = labelDefinition(line);
    if (!label) continue;
    if (label.startsWith(".")) {
      if (label === word && parent.length > 0) {
        const start = Math.max(0, line.indexOf(label));
        localDefinitions.push({
          parent,
          location: {
            uri: document.uri,
            range: Range.create(lineIndex, start, lineIndex, start + label.length),
          },
        });
      }
    } else {
      parent = label;
    }
  }

  if (localDefinitions.length === 0) return undefined;

  const referenceParent = parentLabelBefore(lines, referenceLine);
  const exact = localDefinitions.find((entry) => entry.parent === referenceParent);
  return exact?.location ?? localDefinitions[0].location;
}

function parentLabelBefore(lines: string[], line: number): string {
  let parent = "";
  for (let index = 0; index <= line && index < lines.length; index += 1) {
    const label = labelDefinition(stripAssemblerComment(lines[index] ?? ""));
    if (label && !label.startsWith(".")) parent = label;
  }
  return parent;
}

function parentDefinitionLine(lines: string[], parent: string, beforeLine: number): number {
  for (let index = Math.min(beforeLine, lines.length - 1); index >= 0; index -= 1) {
    const label = labelDefinition(stripAssemblerComment(lines[index] ?? ""));
    if (label === parent) return index;
  }
  return 0;
}

function nextParentDefinitionLine(lines: string[], startLine: number): number | undefined {
  for (let index = startLine; index < lines.length; index += 1) {
    const label = labelDefinition(stripAssemblerComment(lines[index] ?? ""));
    if (label && !label.startsWith(".")) return index;
  }
  return undefined;
}

function labelDefinition(line: string): string | undefined {
  const trimmed = line.trim();
  const direct = /^([A-Za-z_.$@][A-Za-z0-9_.$@?]*):/.exec(trimmed);
  if (direct?.[1]) return direct[1];
  const directive = /^label\s+([A-Za-z_.$@][A-Za-z0-9_.$@?]*)\b/i.exec(trimmed);
  return directive?.[1];
}

function stripAssemblerComment(line: string): string {
  let quote: string | undefined;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (quote) {
      if (ch === "\\" && quote !== "`") {
        i += 1;
      } else if (ch === quote) {
        quote = undefined;
      }
      continue;
    }
    if (ch === "\"" || ch === "'" || ch === "`") {
      quote = ch;
      continue;
    }
    if (ch === ";") return line.slice(0, i);
    if (ch === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

function findReferenceLocations(document: TextDocument, word: string): Location[] {
  const seen = new Set<string>();
  const result: Location[] = [];

  addUniqueLocations(result, seen, wordLocations(document.uri, document, word));
  for (const includeDocument of includeChainDocuments(document)) {
    addUniqueLocations(result, seen, wordLocations(includeDocument.uri, includeDocument, word));
  }
  for (const filePath of workspaceSourceFiles()) {
    if (result.length >= 1000) break;
    const uri = pathToFileURL(filePath).toString();
    if (seenHasUri(seen, uri)) continue;
    const workspaceDocument = readDiskDocument(filePath);
    if (!workspaceDocument) continue;
    addUniqueLocations(result, seen, wordLocations(workspaceDocument.uri, workspaceDocument, word));
  }

  return result.slice(0, 1000);
}

function localReferenceLocations(document: TextDocument, word: string, referenceLine: number): Location[] {
  const lines = document.getText().split(/\r?\n/);
  const parent = parentLabelBefore(lines, referenceLine);
  const startLine = parent.length > 0 ? parentDefinitionLine(lines, parent, referenceLine) : 0;
  const endLine = nextParentDefinitionLine(lines, startLine + 1) ?? lines.length;
  const scopedText = lines.slice(startLine, endLine).join("\n");
  const scopedDocument = TextDocument.create(document.uri, "xirasm", document.version, scopedText);

  return wordLocations(document.uri, scopedDocument, word).map((location) => ({
    uri: location.uri,
    range: Range.create(
      location.range.start.line + startLine,
      location.range.start.character,
      location.range.end.line + startLine,
      location.range.end.character,
    ),
  }));
}

function includePathCompletionItems(document: TextDocument, position: { line: number; character: number }): CompletionItem[] | undefined {
  const line = lineText(document, position.line);
  const beforeCursor = line.slice(0, Math.min(position.character, line.length));
  const match = /^\s*(?:import|include)\s*\(\s*(?:"([^"]*)|([^\s)"]*))$/i.exec(beforeCursor);
  if (!match) return undefined;

  const partial = match[1] ?? match[2] ?? "";
  const separator = Math.max(partial.lastIndexOf("/"), partial.lastIndexOf("\\"));
  const directoryPart = separator >= 0 ? partial.slice(0, separator + 1) : "";
  const documentPath = uriToPath(document.uri);
  const roots = includeSearchRoots(documentPath, analysisContext());
  const seen = new Set<string>();
  const items: CompletionItem[] = [];

  for (const root of roots) {
    const directory = path.resolve(root, directoryPart);
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (!entry.isDirectory() && !entry.isFile()) continue;
      if (entry.name.startsWith(".") && entry.name !== ".vscode") continue;
      if (entry.isFile() && !isXirasmSourcePath(entry.name)) continue;
      const label = entry.isDirectory() ? `${entry.name}/` : entry.name;
      const key = `${entry.isDirectory() ? "dir" : "file"}:${directoryPart}${label}`;
      if (seen.has(key)) continue;
      seen.add(key);
      items.push({
        label,
        kind: entry.isDirectory() ? CompletionItemKind.Folder : CompletionItemKind.File,
        insertText: label,
        detail: entry.isDirectory() ? "include directory" : "XIRASM include file",
      });
    }
  }

  return items.slice(0, 200);
}

function symbolCompletionItems(document: TextDocument): CompletionItem[] {
  const seen = new Set(allCompletionItems.map((entry) => entry.label));
  const result: CompletionItem[] = [];
  for (const sourceDocument of [document, ...includeChainDocuments(document)]) {
    const filePath = uriToPath(sourceDocument.uri);
    const detailPath = filePath ? path.relative(workspaceRoots[0] ?? path.dirname(filePath), filePath) : "current file";
    for (const symbol of analyzeDocument(sourceDocument, analysisContext()).symbols) {
      if (seen.has(symbol.name)) continue;
      seen.add(symbol.name);
      result.push({
        label: symbol.name,
        kind: completionKindForSymbol(symbol.kind),
        detail: `${symbolKindName(symbol.kind)} from ${detailPath}`,
      });
      if (result.length >= 300) return result;
    }
  }
  return result;
}

function symbolHover(document: TextDocument, word: string, position: { line: number; character: number }): Hover | null {
  if (!word) return null;
  if (word.startsWith(".")) {
    const scoped = scopedLocalSymbolLocation(document, word, position.line);
    if (scoped) {
      const filePath = uriToPath(scoped.uri);
      const displayPath = filePath ? path.relative(workspaceRoots[0] ?? path.dirname(filePath), filePath) : "current file";
      const documentation = documentationBeforeLine(document, scoped.range.start.line);
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: hoverText(word, `local label defined in \`${displayPath}:${scoped.range.start.line + 1}\`.`, documentation),
        },
      };
    }
  }

  for (const sourceDocument of [document, ...includeChainDocuments(document)]) {
    const symbol = analyzeDocument(sourceDocument, analysisContext()).symbols.find((entry) => entry.name === word);
    if (!symbol) continue;
    const filePath = uriToPath(sourceDocument.uri);
    const displayPath = filePath ? path.relative(workspaceRoots[0] ?? path.dirname(filePath), filePath) : "current file";
    const line = symbol.selectionRange.start.line + 1;
    const documentation = documentationBeforeLine(sourceDocument, symbol.range.start.line);
    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: hoverText(symbol.name, `${symbolKindName(symbol.kind)} defined in \`${displayPath}:${line}\`.`, documentation),
      },
    };
  }
  return null;
}

function hoverText(name: string, location: string, documentation: string | undefined): string {
  const parts = [`**${name}**`];
  if (documentation && documentation.length > 0) parts.push(documentation);
  parts.push(location);
  return parts.join("\n\n");
}

function documentationBeforeLine(document: TextDocument, line: number): string | undefined {
  const lines = document.getText().split(/\r?\n/);
  const comments: string[] = [];

  for (let index = line - 1; index >= 0; index -= 1) {
    const comment = wholeLineCommentText(lines[index] ?? "");
    if (comment === undefined) break;
    comments.push(comment);
  }

  if (comments.length === 0) return undefined;
  return comments.reverse().join("\n");
}

function wholeLineCommentText(line: string): string | undefined {
  const trimmed = line.trimStart();
  if (trimmed.startsWith(";")) return trimmed.slice(1).trimStart();
  if (trimmed.startsWith("//")) return trimmed.slice(2).trimStart();
  return undefined;
}

function includeChainDocuments(document: TextDocument): TextDocument[] {
  const visited = new Set<string>();
  const queue = literalIncludes(document, analysisContext())
    .map((entry) => entry.resolvedPath)
    .filter((value): value is string => value !== undefined);
  const result: TextDocument[] = [];

  while (queue.length > 0 && visited.size < 64) {
    const includePath = queue.shift()!;
    const normalized = path.resolve(includePath);
    if (visited.has(normalized)) continue;
    visited.add(normalized);

    const includeDocument = readDiskDocument(normalized);
    if (!includeDocument) continue;
    result.push(includeDocument);
    for (const include of literalIncludes(includeDocument, analysisContext())) {
      if (include.resolvedPath) queue.push(include.resolvedPath);
    }
  }

  return result;
}

function symbolLocations(uri: string, document: TextDocument, word: string): Location[] {
  const analysis = analyzeDocument(document, analysisContext());
  return analysis.symbols
    .filter((entry) => entry.name === word)
    .map((entry) => ({
      uri,
      range: entry.selectionRange,
    }));
}

function extensionIncludeRoots(): string[] {
  if (!extensionRoot) return [];
  return [
    path.resolve(extensionRoot, "resources", "include"),
    path.resolve(extensionRoot, "..", "..", "..", "include"),
  ];
}

function readDiskDocument(filePath: string): TextDocument | undefined {
  try {
    const text = fs.readFileSync(filePath, "utf8");
    return TextDocument.create(pathToFileURL(filePath).toString(), "xirasm", 1, text);
  } catch {
    return undefined;
  }
}

function addWorkspaceSymbols(
  target: WorkspaceSymbol[],
  seen: Set<string>,
  uri: string,
  document: TextDocument,
  query: string,
): void {
  const analysis = analyzeDocument(document, analysisContext());
  for (const symbol of analysis.symbols) {
    if (query.length > 0 && !symbol.name.toLowerCase().includes(query)) continue;
    const key = `${uri}:${symbol.name}:${symbol.selectionRange.start.line}:${symbol.selectionRange.start.character}`;
    if (seen.has(key)) continue;
    seen.add(key);
    target.push({
      name: symbol.name,
      kind: symbol.kind,
      location: {
        uri,
        range: symbol.selectionRange,
      },
    });
    if (target.length >= 500) return;
  }
}

function workspaceSourceFiles(): string[] {
  const result: string[] = [];
  for (const root of workspaceRoots) {
    collectSourceFiles(root, result);
    if (result.length >= 1000) break;
  }
  return result;
}

function collectSourceFiles(dir: string, result: string[]): void {
  if (result.length >= 1000 || shouldSkipDir(dir)) return;
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (result.length >= 1000) return;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectSourceFiles(fullPath, result);
    } else if (entry.isFile() && isXirasmSourcePath(fullPath)) {
      result.push(fullPath);
    }
  }
}

function shouldSkipDir(dir: string): boolean {
  const name = path.basename(dir).toLowerCase();
  return name === ".git" ||
    name === ".zig-cache" ||
    name === "zig-out" ||
    name === "node_modules" ||
    name === "tmp" ||
    name === "target" ||
    (name.startsWith(".") && name !== ".vscode");
}

function isXirasmSourcePath(filePath: string): boolean {
  const ext = path.extname(filePath).toLowerCase();
  return ext === ".asm" || ext === ".inc" || ext === ".xir";
}

function wordLocations(uri: string, document: TextDocument, word: string): Location[] {
  const lines = document.getText().split(/\r?\n/);
  const result: Location[] = [];
  const pattern = new RegExp(`(^|[^A-Za-z0-9_.$@!?])(${escapeRegExp(word)})(?=$|[^A-Za-z0-9_.$@!?])`, "g");

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    pattern.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(line)) !== null) {
      const prefix = match[1] ?? "";
      const start = match.index + prefix.length;
      result.push({
        uri,
        range: Range.create(lineIndex, start, lineIndex, start + word.length),
      });
      if (match.index === pattern.lastIndex) pattern.lastIndex += 1;
    }
  }

  return result;
}

function addUniqueLocations(target: Location[], seen: Set<string>, locations: Location[]): void {
  for (const location of locations) {
    const key = `${location.uri}:${location.range.start.line}:${location.range.start.character}:${location.range.end.character}`;
    if (seen.has(key)) continue;
    seen.add(key);
    target.push(location);
  }
}

function seenHasUri(seen: Set<string>, uri: string): boolean {
  for (const key of seen) {
    if (key.startsWith(`${uri}:`)) return true;
  }
  return false;
}

function lineText(document: TextDocument, lineNumber: number): string {
  return document.getText().split(/\r?\n/)[lineNumber] ?? "";
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const normalized = path.resolve(value);
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function ancestorDirectories(start: string): string[] {
  const result: string[] = [];
  let cursor = path.resolve(start);
  while (true) {
    result.push(cursor);
    const parent = path.dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }
  return result;
}

function completionKindForSymbol(kind: SymbolKind): CompletionItemKind {
  switch (kind) {
    case SymbolKind.Function:
      return CompletionItemKind.Function;
    case SymbolKind.Struct:
      return CompletionItemKind.Struct;
    case SymbolKind.Enum:
      return CompletionItemKind.Enum;
    case SymbolKind.Field:
      return CompletionItemKind.Field;
    case SymbolKind.Namespace:
      return CompletionItemKind.Module;
    case SymbolKind.Variable:
      return CompletionItemKind.Variable;
    default:
      return CompletionItemKind.Reference;
  }
}

function symbolKindName(kind: SymbolKind): string {
  switch (kind) {
    case SymbolKind.Function:
      return "function";
    case SymbolKind.Struct:
      return "structure";
    case SymbolKind.Enum:
      return "enum";
    case SymbolKind.Field:
      return "field";
    case SymbolKind.Namespace:
      return "namespace label";
    case SymbolKind.Variable:
      return "variable";
    case SymbolKind.String:
      return "label";
    default:
      return "symbol";
  }
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function assembleDiagnostics(document: TextDocument): Promise<Diagnostic[]> {
  const assembler = settings.diagnostics.assembler;
  if (!assembler.enabled) return [];

  const sourcePath = uriToPath(document.uri);
  if (!sourcePath) return [];
  const executable = findAssemblerExecutable(assembler.executablePath);
  if (!executable) return [];

  const cwd = workspaceRoots[0] ?? path.dirname(sourcePath);
  const timeoutMs = Math.max(250, assembler.timeoutMs);
  const result = await runAssembler(executable, sourcePath, cwd, timeoutMs);
  if (result.exitCode === 0) return [];

  return parseAssemblerDiagnostics(document, result.stderr || result.stdout || "assembler failed");
}

function findAssemblerExecutable(configuredPath: string): string | undefined {
  if (configuredPath.trim().length > 0) return configuredPath;
  for (const root of workspaceRoots) {
    const exe = path.join(root, "zig-out", "bin", process.platform === "win32" ? "xirasm.exe" : "xirasm");
    if (fs.existsSync(exe)) return exe;
  }
  return "xirasm";
}

function runAssembler(executable: string, sourcePath: string, cwd: string, timeoutMs: number): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    let tempDir: string | undefined;
    let outputPath: string;
    try {
      tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xirasm-lsp-"));
      outputPath = path.join(tempDir, "out.bin");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      resolve({ exitCode: null, stdout: "", stderr: message });
      return;
    }

    const child = spawn(executable, [sourcePath, "-o", outputPath], {
      cwd,
      windowsHide: true,
      shell: false,
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill();
      cleanupTempDir(tempDir);
      resolve({ exitCode: null, stdout, stderr: `assembler diagnostics timed out after ${timeoutMs}ms` });
    }, timeoutMs);

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", (error: Error) => {
      clearTimeout(timer);
      cleanupTempDir(tempDir);
      resolve({ exitCode: null, stdout, stderr: error.message });
    });
    child.on("close", (exitCode: number | null) => {
      clearTimeout(timer);
      cleanupTempDir(tempDir);
      resolve({ exitCode, stdout, stderr });
    });
  });
}

function cleanupTempDir(tempDir: string | undefined): void {
  if (!tempDir) return;
  try {
    fs.rmSync(tempDir, { recursive: true, force: true });
  } catch {
    // Best-effort cleanup only.
  }
}

function parseAssemblerDiagnostics(document: TextDocument, output: string): Diagnostic[] {
  const cleanOutput = output.replace(/\r/g, "");
  const sourceDiagnostic = /^(.+):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$/m.exec(cleanOutput);
  if (sourceDiagnostic) {
    const line = Math.max(0, Number(sourceDiagnostic[2]) - 1);
    const col = Math.max(0, Number(sourceDiagnostic[3]) - 1);
    return [{
      severity: sourceDiagnostic[4] === "warning" ? 2 : sourceDiagnostic[4] === "note" ? 3 : 1,
      range: Range.create(line, col, line, col + 1),
      message: sourceDiagnostic[5],
      source: "xirasm",
    }];
  }

  const meta = /^meta\s+\S+\s+at\s+(\d+):(\d+):\s+(.+)$/m.exec(cleanOutput);
  if (meta) {
    const line = Math.max(0, Number(meta[1]) - 1);
    const col = Math.max(0, Number(meta[2]) - 1);
    return [{
      severity: 1,
      range: Range.create(line, col, line, col + 1),
      message: meta[3],
      source: "xirasm",
    }];
  }

  const firstError = /^error:\s*(.+)$/m.exec(cleanOutput);
  const message = firstError?.[1] ?? cleanOutput.split("\n").find((line) => line.trim().length > 0) ?? "assembler failed";
  return [{
    severity: 1,
    range: Range.create(0, 0, 0, Math.max(1, firstLineLength(document))),
    message: `Assembler failed: ${message}`,
    source: "xirasm",
  }];
}

function firstLineLength(document: TextDocument): number {
  const text = document.getText();
  const newline = text.search(/\r?\n/);
  return newline < 0 ? text.length : newline;
}

function normalizeSettings(raw: unknown): ServerSettings {
  const root = isRecord(raw) ? raw : {};
  const diagnostics = isRecord(root.diagnostics) ? root.diagnostics : {};
  const assembler = isRecord(diagnostics.assembler) ? diagnostics.assembler : {};
  return {
    diagnostics: {
      assembler: {
        enabled: typeof assembler.enabled === "boolean" ? assembler.enabled : true,
        executablePath: typeof assembler.executablePath === "string" ? assembler.executablePath : "",
        timeoutMs: typeof assembler.timeoutMs === "number" ? assembler.timeoutMs : 5000,
      },
    },
  };
}

function defaultSettings(): ServerSettings {
  return normalizeSettings(undefined);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

documents.listen(connection);
connection.listen();
