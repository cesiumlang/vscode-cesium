// Cesium for VS Code: a thin client of the language server, as zfls's is
// (#2). It finds the server, starts it for Cesium files, and restarts it
// when a setting changes or on the command; everything else is the
// server's. Highlighting, comments, brackets and indentation are declared in
// package.json.

import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions } from "vscode-languageclient/node";
import { ensureExecutable, findServer, resolveSetting, SERVER_NAME } from "./executable";

/** The settings the server is started with: a change restarts it */
const SERVER_SETTINGS = ["cesium.server.path", "cesium.compiler.path"];

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
      if (SERVER_SETTINGS.some((s) => e.affectsConfiguration(s))) {
        output.info("A setting of the language server changed: restarting it");
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
    initializationOptions: {
      compiler: { path: resolveSetting(config.get<string>("compiler.path", ""), base) },
    },
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
