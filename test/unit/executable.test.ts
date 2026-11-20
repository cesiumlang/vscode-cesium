// Plain Node.js tests of finding the language server (src/executable.ts)

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { test } from "node:test";
import { findServer, resolveSetting, SERVER_NAME } from "../../src/executable";

const exe = process.platform === "win32" ? `${SERVER_NAME}.exe` : SERVER_NAME;

function tempDirs(...names: string[]): string[] {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "cesium-unit-"));
  return names.map((n) => {
    const d = path.join(root, n);
    fs.mkdirSync(d);
    return d;
  });
}

test("resolveSetting: home, relative and absolute paths", () => {
  const home = path.resolve("/home/me");
  const base = path.resolve("/work");
  assert.equal(resolveSetting("", base, home), "");
  assert.equal(resolveSetting("  ", base, home), "");
  assert.equal(resolveSetting("~", base, home), home);
  assert.equal(resolveSetting("~/bin/zcsls", base, home), path.join(home, "bin", "zcsls"));
  assert.equal(resolveSetting("tools/zcsls", base, home), path.resolve(base, "tools/zcsls"));
  assert.equal(resolveSetting("tools/zcsls", undefined, home), "tools/zcsls");
  const abs = path.resolve("/opt/zcsls");
  assert.equal(resolveSetting(abs, base, home), abs);
});

test("findServer: the setting, then bin/, then the PATH", () => {
  const [bin, onPath, empty] = tempDirs("bin", "path", "empty");
  fs.writeFileSync(path.join(onPath, exe), "");
  const env = { PATH: [empty, onPath].join(path.delimiter) };
  assert.deepEqual(findServer("", bin, env), { command: path.join(onPath, exe) });
  fs.writeFileSync(path.join(bin, exe), "");
  assert.deepEqual(findServer("", bin, env), { command: path.join(bin, exe) });
  const configured = path.join(empty, "mine");
  assert.deepEqual(findServer(configured, bin, env), { tried: configured });
  fs.writeFileSync(configured, "");
  assert.deepEqual(findServer(configured, bin, env), { command: configured });
  assert.deepEqual(findServer("", empty, { PATH: empty }), {});
});
