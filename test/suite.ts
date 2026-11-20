// Runs inside VS Code (test/runTest.ts): the extension activates, and the
// fixture's .csm and .csi files open as the language cesium. CESIUM_VERSION,
// when set, is the version the packaged extension must have.

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";

export async function run(): Promise<void> {
  const ext = vscode.extensions.getExtension("cesiumlang.cesium");
  assert.ok(ext, "the extension cesiumlang.cesium is not installed");
  await ext.activate();
  const want = process.env.CESIUM_VERSION;
  if (want) assert.equal(ext.packageJSON.version, want, "version of the packaged extension");

  const folder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  assert.ok(folder, "no workspace folder");
  for (const name of ["main.csm", "main.csi"]) {
    const doc: vscode.TextDocument = await vscode.workspace.openTextDocument(path.join(folder, name));
    await vscode.window.showTextDocument(doc);
    assert.equal(doc.languageId, "cesium", name);
  }
  console.log(`cesiumlang.cesium ${ext.packageJSON.version}: .csm and .csi files are cesium`);
}
