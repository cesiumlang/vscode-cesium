// Runs test/suite.ts inside a downloaded VS Code with only this extension,
// on the fixture workspace test/fixture (`npm test`; CI runs it on Linux,
// macOS and Windows). CESIUM_EXTENSION_PATH, when set, is an unpacked VSIX
// (its `extension` directory), to test the packaged extension.
// CESIUM_DIAGNOSTICS, when set, also tests the language server's
// diagnostics, which needs zcsls and cesium1 (test/suite.ts).

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runTests } from "@vscode/test-electron";

async function main(): Promise<void> {
  // set in VS Code's own terminals; the VS Code under test would then start
  // as plain Node.js
  delete process.env.ELECTRON_RUN_AS_NODE;
  const root = path.resolve(__dirname, "..");
  const extensionDevelopmentPath = process.env.CESIUM_EXTENSION_PATH
    ? path.resolve(process.env.CESIUM_EXTENSION_PATH)
    : root;
  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath: path.resolve(__dirname, "suite.js"),
    // fresh settings each run
    launchArgs: [
      path.join(root, "test", "fixture"),
      "--disable-extensions",
      "--disable-workspace-trust",
      // CI runs on virtual displays, where GPU start-up can hang the window
      "--disable-gpu",
      `--user-data-dir=${fs.mkdtempSync(path.join(os.tmpdir(), "cesium-vscode-"))}`,
    ],
    extensionTestsEnv: {
      CESIUM_VERSION: process.env.CESIUM_VERSION ?? "",
      CESIUM_DIAGNOSTICS: process.env.CESIUM_DIAGNOSTICS ?? "",
    },
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
