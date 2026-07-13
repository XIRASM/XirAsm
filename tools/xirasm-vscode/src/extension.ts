import * as path from "path";
import * as vscode from "vscode";
import { ExtensionContext } from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;

export function activate(context: ExtensionContext): void {
  const serverModule = context.asAbsolutePath(path.join("out", "server.js"));
  const serverOptions: ServerOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: { execArgv: ["--nolazy", "--inspect=6009"] },
    },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "xirasm" }],
    initializationOptions: {
      settings: readSettings(),
      extensionRoot: context.extensionPath,
    },
    synchronize: {
      configurationSection: "xirasm",
      fileEvents: [],
    },
  };

  client = new LanguageClient("xirasmLanguageServer", "XIRASM Language Server", serverOptions, clientOptions);
  context.subscriptions.push(client);
  client.start().catch((error: unknown) => {
    console.error("Failed to start XIRASM language server", error);
  });
}

function readSettings(): unknown {
  const config = vscode.workspace.getConfiguration("xirasm");
  return {
    diagnostics: {
      assembler: {
        enabled: config.get<boolean>("diagnostics.assembler.enabled", true),
        executablePath: config.get<string>("diagnostics.assembler.executablePath", ""),
        timeoutMs: config.get<number>("diagnostics.assembler.timeoutMs", 5000),
      },
    },
  };
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
