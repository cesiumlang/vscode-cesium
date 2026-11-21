// Runs inside VS Code (test/runTest.ts): the extension activates, and the
// fixture's .csm and .csi files open as the language cesium. CESIUM_VERSION,
// when set, is the version the packaged extension must have. With
// CESIUM_DIAGNOSTICS set (CI, with a cesium1 on the PATH and a platform
// VSIX), the language server reports the error of error/unknown_name.csm.

import * as assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";

export async function run(): Promise<void> {
  const ext = vscode.extensions.getExtension("cesiumlang.vscode-cesium");
  assert.ok(ext, "the extension cesiumlang.vscode-cesium is not installed");
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
  console.log(`cesiumlang.vscode-cesium ${ext.packageJSON.version}: .csm and .csi files are cesium`);

  if (!process.env.CESIUM_DIAGNOSTICS) {
    console.log("diagnostics not tested: CESIUM_DIAGNOSTICS is not set (no cesium1)");
    return;
  }
  const bad = vscode.Uri.file(path.join(folder, "error", "unknown_name.csm"));
  await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(bad));
  const diags = await diagnosticsOf(bad, 60_000);
  assert.equal(diags.length, 1, "one diagnostic");
  assert.equal(diags[0].message, "unknown name 'x'");
  assert.equal(diags[0].source, "cesium1");
  assert.equal(diags[0].severity, vscode.DiagnosticSeverity.Error);
  assert.deepEqual([diags[0].range.start.line, diags[0].range.start.character], [3, 9], "where the error is");
  // checked before, and valid
  assert.equal(vscode.languages.getDiagnostics(vscode.Uri.file(path.join(folder, "main.csm"))).length, 0, "main.csm has no diagnostics");
  console.log(`the language server reports: ${diags[0].message}`);
}

/** The diagnostics of `uri` once there are some, waiting at most `ms` */
function diagnosticsOf(uri: vscode.Uri, ms: number): Promise<readonly vscode.Diagnostic[]> {
  return new Promise((resolve, reject) => {
    const now = vscode.languages.getDiagnostics(uri);
    if (now.length > 0) {
      resolve(now);
      return;
    }
    const timer = setTimeout(() => {
      sub.dispose();
      reject(new Error(`no diagnostics of ${uri.fsPath} within ${ms} ms`));
    }, ms);
    const sub = vscode.languages.onDidChangeDiagnostics((e) => {
      if (!e.uris.some((u) => u.toString() === uri.toString())) return;
      const d = vscode.languages.getDiagnostics(uri);
      if (d.length === 0) return;
      clearTimeout(timer);
      sub.dispose();
      resolve(d);
    });
  });
}
