// Tests of the indentation rules of language-configuration.json with plain
// Node.js (no VS Code), applied as VS Code applies them: `new RegExp(pattern)`
// on one line (`npm run unit`).
// increaseIndentPattern: the line after this one is indented.
// decreaseIndentPattern: this line is outdented as it is typed.

import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { test } from "node:test";

const root = path.join(__dirname, "..", "..");
const rules = JSON.parse(fs.readFileSync(path.join(root, "language-configuration.json"), "utf8")).indentationRules;
const increase = new RegExp(rules.increaseIndentPattern);
const decrease = new RegExp(rules.decreaseIndentPattern);

/** Lines and what they do: `in` indents the next line, `out` outdents
 * itself, `both` does both, `none` neither */
const table: [string, "in" | "out" | "both" | "none"][] = [
  ["i32 = main() {", "in"],
  ["struct Point {", "in"],
  ["if (x > 0) {", "in"],
  ["i32 = f(", "in"],
  ["i32 xs[3] = [", "in"],
  ["while (true) { // loop", "in"],
  ["}", "out"],
  ["};", "out"],
  [")", "out"],
  ["];", "out"],
  ["   end of a block comment */ }", "out"],
  ["} else {", "both"],
  ["}) {", "both"],
  ["return 0;", "none"],
  ["str s = \"{\";", "none"],
  ["str s = `{name}`;", "none"],
  ["u8 c = '(';", "none"],
  ["// if (x) {", "none"],
  ["x = f(1) + g[2];", "none"],
];

test("indentation rules", () => {
  for (const [line, want] of table) {
    const got = increase.test(line) ? (decrease.test(line) ? "both" : "in") : decrease.test(line) ? "out" : "none";
    assert.equal(got, want, line);
  }
});
