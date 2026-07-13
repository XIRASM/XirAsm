import * as fs from "fs";
import * as path from "path";
import {
  Diagnostic,
  DiagnosticSeverity,
  DocumentSymbol,
  Position,
  Range,
  SymbolKind,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

export type AnalysisContext = {
  workspaceRoots: string[];
};

export type IncludeReference = {
  path: string;
  resolvedPath?: string;
  range: Range;
};

type BlockRule = {
  kind: string;
  open: RegExp;
};

type BlockFrame = {
  kind: string;
  line: number;
  range: Range;
};

const blockRules: BlockRule[] = [
  rule("fn", /^fn\b.*\{\s*$/),
  rule("if", /^if\b.*\{\s*$/),
  rule("else", /^\}?\s*else\b.*\{\s*$/),
  rule("while", /^while\b.*\{\s*$/),
  rule("for", /^for\b.*\{\s*$/),
  rule("defer", /^defer\b.*\{\s*$/),
  rule("struct", /^(?:packed\s+)?struct\b.*\{\s*$/),
  rule("union", /^(?:packed\s+)?union\b.*\{\s*$/),
  rule("enum", /^enum\b.*\{\s*$/),
];

const symbolRules: Array<{ kind: SymbolKind; regex: RegExp }> = [
  { kind: SymbolKind.Function, regex: /^\s*fn\s+([A-Za-z_.$@][A-Za-z0-9_.$@?]*)/ },
  { kind: SymbolKind.Struct, regex: /^\s*(?:packed\s+)?struct\s+([A-Za-z_.$@][A-Za-z0-9_.$@?]*)/ },
  { kind: SymbolKind.Struct, regex: /^\s*(?:packed\s+)?union\s+([A-Za-z_.$@][A-Za-z0-9_.$@?]*)/ },
  { kind: SymbolKind.Enum, regex: /^\s*enum\s+([A-Za-z_.$@][A-Za-z0-9_.$@?]*)/ },
  { kind: SymbolKind.Variable, regex: /^\s*(?:const|let|var)\s+([A-Za-z_.$@][A-Za-z0-9_.$@?]*)/ },
  { kind: SymbolKind.String, regex: /^\s*([A-Za-z_.$@][A-Za-z0-9_.$@?]*):/ },
];

export function analyzeDocument(document: TextDocument, context: AnalysisContext): { diagnostics: Diagnostic[]; symbols: DocumentSymbol[] } {
  const text = document.getText();
  const lines = text.split(/\r?\n/);
  const diagnostics: Diagnostic[] = [];
  const symbols: DocumentSymbol[] = [];
  const stack: BlockFrame[] = [];
  const labels = new Map<string, Range>();
  const documentPath = uriToPath(document.uri);

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const rawLine = lines[lineIndex];
    const trimmed = stripAssemblerComment(rawLine).trim();
    if (trimmed.length === 0) continue;

    collectSymbol(rawLine, lineIndex, symbols, labels, diagnostics);
    checkInclude(trimmed, lineIndex, documentPath, context, diagnostics);
    updateBlockStack(trimmed, lineIndex, rawLine.length, stack, diagnostics);
  }

  for (const frame of stack.reverse()) {
    diagnostics.push({
      severity: DiagnosticSeverity.Warning,
      range: frame.range,
      message: `Unclosed ${frame.kind} block.`,
      source: "xirasm-lsp",
    });
  }

  return { diagnostics, symbols };
}

export function wordAt(text: string, position: Position): string {
  const lines = text.split(/\r?\n/);
  const line = lines[position.line] ?? "";
  const index = Math.min(position.character, line.length);
  const chars = /[A-Za-z0-9_.$@!?]/;
  let start = index;
  while (start > 0 && chars.test(line[start - 1] ?? "")) start -= 1;
  let end = index;
  while (end < line.length && chars.test(line[end] ?? "")) end += 1;
  return line.slice(start, end);
}

export function literalIncludes(document: TextDocument, context: AnalysisContext): IncludeReference[] {
  const text = document.getText();
  const lines = text.split(/\r?\n/);
  const documentPath = uriToPath(document.uri);
  const result: IncludeReference[] = [];

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    const include = parseInclude(line);
    if (!include) continue;
    result.push({
      path: include.path,
      resolvedPath: resolveIncludePath(include.path, documentPath, context),
      range: Range.create(lineIndex, include.start, lineIndex, include.end),
    });
  }

  return result;
}

export function includeAtPosition(document: TextDocument, position: Position, context: AnalysisContext): IncludeReference | undefined {
  return literalIncludes(document, context).find((entry) =>
    entry.range.start.line === position.line &&
    entry.range.start.character <= position.character &&
    position.character <= entry.range.end.character,
  );
}

function updateBlockStack(trimmed: string, line: number, lineLength: number, stack: BlockFrame[], diagnostics: Diagnostic[]): void {
  const closeCount = countUnquoted(trimmed, "}");
  for (let index = 0; index < closeCount; index += 1) {
    const frame = stack.pop();
    if (!frame) {
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: lineRange(line, lineLength),
        message: "Unexpected `}` without matching block.",
        source: "xirasm-lsp",
      });
    }
  }

  if (/^\s*\}?\s*else\b/.test(trimmed) && closeCount === 0 && !stack.some((frame) => frame.kind === "if")) {
    diagnostics.push({
      severity: DiagnosticSeverity.Warning,
      range: lineRange(line, lineLength),
      message: "`else` appears outside an `if` block.",
      source: "xirasm-lsp",
    });
  }

  const openCount = countUnquoted(trimmed, "{");
  let pushed = false;
  for (const candidate of blockRules) {
    if (!candidate.open.test(trimmed)) continue;
    stack.push({ kind: candidate.kind, line, range: lineRange(line, lineLength) });
    pushed = true;
    break;
  }
  for (let index = pushed ? 1 : 0; index < openCount; index += 1) {
    stack.push({ kind: "block", line, range: lineRange(line, lineLength) });
  }
}

function collectSymbol(
  line: string,
  lineIndex: number,
  symbols: DocumentSymbol[],
  labels: Map<string, Range>,
  diagnostics: Diagnostic[],
): void {
  for (const ruleDef of symbolRules) {
    const match = ruleDef.regex.exec(line);
    if (!match?.[1]) continue;
    const name = match[1];
    const start = line.indexOf(name);
    const range = Range.create(lineIndex, Math.max(0, start), lineIndex, Math.max(0, start) + name.length);
    symbols.push({
      name,
      kind: ruleDef.kind,
      range: lineRange(lineIndex, line.length),
      selectionRange: range,
    });

    if (!name.startsWith(".")) {
      const existing = labels.get(name);
      if (existing) {
        diagnostics.push({
          severity: DiagnosticSeverity.Information,
          range,
          message: `Symbol '${name}' also appears earlier in this file.`,
          source: "xirasm-lsp",
        });
      } else {
        labels.set(name, range);
      }
    }
    return;
  }
}

function checkInclude(
  trimmed: string,
  lineIndex: number,
  documentPath: string | undefined,
  context: AnalysisContext,
  diagnostics: Diagnostic[],
): void {
  const include = parseInclude(trimmed);
  if (!include) return;
  const includePath = include.path;
  if (includePath.includes("$") || includePath.includes("#")) return;

  if (resolveIncludePath(includePath, documentPath, context)) return;
  diagnostics.push({
    severity: DiagnosticSeverity.Hint,
    range: lineRange(lineIndex, trimmed.length),
    message: `Import target '${includePath}' was not found relative to this file, project include/, or bundled include resources.`,
    source: "xirasm-lsp",
  });
}

export function resolveIncludePath(includePath: string, documentPath: string | undefined, context: AnalysisContext): string | undefined {
  if (includePath.includes("$") || includePath.includes("#")) return undefined;

  const candidates: string[] = [];
  for (const root of includeSearchRoots(documentPath, context)) {
    candidates.push(path.resolve(root, includePath));
  }

  return uniqueExistingPath(candidates);
}

export function includeSearchRoots(documentPath: string | undefined, context: AnalysisContext): string[] {
  const roots: string[] = [];
  if (documentPath) {
    roots.push(path.dirname(documentPath));
    for (const root of ancestorDirectories(path.dirname(documentPath))) {
      roots.push(root);
      roots.push(path.resolve(root, "include"));
    }
  }
  for (const root of context.workspaceRoots) {
    roots.push(root);
    roots.push(path.resolve(root, "include"));
  }
  return uniquePaths(roots);
}

function parseInclude(line: string): { path: string; start: number; end: number } | undefined {
  const source = stripAssemblerComment(line);
  const match = /^\s*(?:import|include)\s*\(\s*"([^"]+)"\s*\)/i.exec(source);
  const includePath = match?.[1];
  if (!includePath) return undefined;
  const start = source.indexOf(includePath);
  return {
    path: includePath,
    start: Math.max(0, start),
    end: Math.max(0, start) + includePath.length,
  };
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

function uniqueExistingPath(candidates: string[]): string | undefined {
  const seen = new Set<string>();
  for (const candidate of candidates) {
    const normalized = path.resolve(candidate);
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    if (fs.existsSync(normalized)) return normalized;
  }
  return undefined;
}

function uniquePaths(paths: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const candidate of paths) {
    const normalized = path.resolve(candidate);
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function stripAssemblerComment(line: string): string {
  let quote = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (quote) {
      if (ch === "\"" && line[i + 1] === "\"") {
        i += 1;
      } else if (ch === "\"") {
        quote = false;
      }
      continue;
    }
    if (ch === "\"") {
      quote = true;
      continue;
    }
    if (ch === ";") return line.slice(0, i);
    if (ch === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

function countUnquoted(line: string, needle: string): number {
  let quote = false;
  let count = 0;
  for (let index = 0; index < line.length; index += 1) {
    const ch = line[index];
    if (quote) {
      if (ch === "\"" && line[index + 1] === "\"") {
        index += 1;
      } else if (ch === "\"") {
        quote = false;
      }
      continue;
    }
    if (ch === "\"") {
      quote = true;
      continue;
    }
    if (ch === needle) count += 1;
  }
  return count;
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

function lineRange(line: number, lineLength: number): Range {
  return Range.create(line, 0, line, Math.max(1, lineLength));
}

function rule(kind: string, open: RegExp): BlockRule {
  return { kind, open };
}
