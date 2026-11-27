// Plain Node.js tests (no VS Code) that the files package.json names exist
// (`npm run unit`); the grammar is the submodule grammar/.

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { test } from "node:test";

const root = path.join(__dirname, "..", "..");
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));

test("the icon, language files and grammar exist", () => {
  const files: string[] = [pkg.icon];
  for (const l of pkg.contributes.languages) files.push(l.configuration, l.icon.light, l.icon.dark);
  for (const g of pkg.contributes.grammars) files.push(g.path);
  for (const f of files) assert.ok(fs.existsSync(path.join(root, f)), `${f} is missing (git submodule update --init?)`);
});

test("the chat skill and instructions exist, and the instructions are for Cesium files", () => {
  assert.ok(pkg.contributes.chatSkills.length > 0 && pkg.contributes.chatInstructions.length > 0);
  for (const c of [...pkg.contributes.chatSkills, ...pkg.contributes.chatInstructions]) {
    assert.ok(fs.existsSync(path.join(root, c.path)), `${c.path} is missing (bash tools/fetch-skill.sh)`);
  }
  for (const s of pkg.contributes.chatSkills) {
    assert.match(fs.readFileSync(path.join(root, s.path), "utf8"), /^---\nname: cesium-language\n/);
  }
  for (const i of pkg.contributes.chatInstructions) assert.equal(i.when, "resourceLangId == cesium");
});

test("breakpoints can be set in Cesium files, for any debugger", () => {
  assert.deepEqual(pkg.contributes.breakpoints, [{ language: "cesium" }]);
});

test("the grammar has the scope package.json gives it", () => {
  for (const g of pkg.contributes.grammars) {
    const grammar = JSON.parse(fs.readFileSync(path.join(root, g.path), "utf8"));
    assert.equal(grammar.scopeName, g.scopeName);
  }
});
