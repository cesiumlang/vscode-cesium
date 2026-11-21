// Cesium for VS Code: a thin client of the language server, as zfls's is
// (#2). It finds the server and starts it for Cesium files, passes the
// cesium.* settings to it at start-up and when they change, and restarts it
// when cesium.server.path changes or on the command; everything else is the
// server's. Highlighting, comments, brackets and indentation are declared in
// package.json.

import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions } from "vscode-languageclient/node";
import { ensureExecutable, findServer, resolveSetting, SERVER_NAME } from "./executable";

/** The setting that names the server: a change restarts it */
const SERVER_PATH = "cesium.server.path";

let context: vscode.ExtensionContext;
let output: vscode.LogOutputChannel;
let client: LanguageClient | undefined;
/** Serializes starts and stops */
let pending: Promise<void> = Promise.resolve();

export async function activate(ctx: vscode.ExtensionContext): Promise<void> {
  context = ctx;
  output = vscode.window.createOutputChannel(vscode.l10n.t("Cesium Language Server"), { log: true });
  ctx.subscriptions.push(
    output,
    vscode.commands.registerCommand("cesium.restartServer", () => restart()),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration(SERVER_PATH)) {
        output.info(`${SERVER_PATH} changed: restarting the language server`);
        void restart();
      }
    }),
  );
  await restart();
}

export async function deactivate(): Promise<void> {
  await stop();
}

/** Stops the server, if it runs, and starts it again */
function restart(): Promise<void> {
  pending = pending.then(async () => {
    await stop();
    await start();
  });
  return pending;
}

async function stop(): Promise<void> {
  const c = client;
  client = undefined;
  if (c) {
    try {
      await c.stop();
    } catch (err) {
      output.warn(`stopping the language server: ${String(err)}`);
    }
  }
}

async function start(): Promise<void> {
  const config = vscode.workspace.getConfiguration("cesium");
  const base = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  const { command, tried } = findServer(
    resolveSetting(config.get<string>("server.path", ""), base),
    context.asAbsolutePath("bin"),
  );
  if (!command) {
    const message = tried
      ? vscode.l10n.t("Cesium: there is no language server at {0}, which cesium.server.path names.", tried)
      : vscode.l10n.t("Cesium: no language server found. Set cesium.server.path, or put {0} on the PATH.", SERVER_NAME);
    output.error(message);
    void vscode.window.showErrorMessage(message, vscode.l10n.t("Open Settings")).then((choice) => {
      if (choice) {
        void vscode.commands.executeCommand("workbench.action.openSettings", "cesium.server.path");
      }
    });
    return;
  }
  if (command.startsWith(context.extensionPath)) {
    ensureExecutable(command);
  }
  output.info(`Starting ${command}`);
  // no `transport`: standard I/O is the default, and TransportKind.stdio
  // would also pass --stdio
  const executable = { command, options: { cwd: base } };
  const serverOptions: ServerOptions = { run: executable, debug: executable };
  const clientOptions: LanguageClientOptions = {
    // the server reads the files of a unit from disk; an untitled document
    // is a unit of its own
    documentSelector: [
      { scheme: "file", language: "cesium" },
      { scheme: "untitled", language: "cesium" },
    ],
    // the server takes the settings as they are and resolves their paths;
    // later changes are sent to it (workspace/didChangeConfiguration)
    initializationOptions: { cesium: vscode.workspace.getConfiguration().get("cesium") },
    synchronize: { configurationSection: "cesium" },
    // vscode-languageclient pulls diagnostics only on open by default
    diagnosticPullOptions: { onChange: true, onSave: true },
    outputChannel: output,
  };
  const c = new LanguageClient("cesium", vscode.l10n.t("Cesium Language Server"), serverOptions, clientOptions);
  try {
    await c.start();
    client = c;
  } catch (err) {
    output.error(`starting ${command}: ${String(err)}`);
    void vscode.window.showErrorMessage(vscode.l10n.t("Cesium: the language server failed to start: {0}", String(err)));
  }
}
