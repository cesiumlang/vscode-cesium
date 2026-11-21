// Plain Node.js tests of the agent plugin (agent-plugin/, #21): its JSON files
// parse, and `.lsp.json` gives zcsls the files and language of package.json
// (`claude plugin validate` does not read `.lsp.json`).

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { test } from "node:test";

const root = path.join(__dirname, "..", "..");

function readJson(file: string): any {
  return JSON.parse(fs.readFileSync(path.join(root, file), "utf8"));
}

const marketplace = readJson(".claude-plugin/marketplace.json");
const pkg = readJson("package.json");

test("the marketplace lists the plugin by its relative path and name", () => {
  assert.equal(typeof marketplace.name, "string");
  assert.equal(typeof marketplace.owner?.name, "string");
  assert.ok(marketplace.plugins.length > 0);
  for (const p of marketplace.plugins) {
    assert.match(p.source, /^\.\/[^.]/, `${p.source}: a relative source starts with ./ and has no ..`);
    const manifest = readJson(path.join(p.source, ".claude-plugin", "plugin.json"));
    assert.equal(manifest.name, p.name);
  }
});

test(".lsp.json starts zcsls for .csm and .csi as the language of package.json", () => {
  const language = pkg.contributes.languages.find((l: any) => l.id === "cesium");
  assert.deepEqual([...language.extensions].sort(), [".csi", ".csm"]);
  for (const p of marketplace.plugins) {
    const servers = Object.values(readJson(path.join(p.source, ".lsp.json"))) as any[];
    assert.equal(servers.length, 1);
    assert.equal(servers[0].command, "zcsls");
    assert.deepEqual(servers[0].extensionToLanguage, { ".csm": "cesium", ".csi": "cesium" });
  }
});

test("each skill has a name and a description", () => {
  for (const p of marketplace.plugins) {
    const skills = path.join(root, p.source, "skills");
    for (const name of fs.readdirSync(skills)) {
      const text = fs.readFileSync(path.join(skills, name, "SKILL.md"), "utf8");
      const front = /^---\r?\n([\s\S]*?)\r?\n---\r?\n/.exec(text);
      assert.ok(front, `${name}: no frontmatter`);
      assert.match(front[1], new RegExp(`^name: ${name}$`, "m"));
      assert.match(front[1], /^description: \S/m);
    }
  }
});
