---
name: cesium-language
description: Writing, reading or reviewing Cesium source (.csm, .csi files) - where the decided syntax and rules are, what is not Cesium, examples that compile, and how to check code with the bootstrap compilers. Use before writing or changing any Cesium code, or when a question depends on Cesium syntax or semantics.
paths:
  - "**/*.csm"
  - "**/*.csi"
---

# Cesium source

No model was trained on Cesium. Do not guess its syntax from C, Zig or C++: check every construct against the sources below, and run a compiler on what you write.

## Where the truth is, in this order

1. **The S0 grammar,** for anything `cesium0` and `cesium1` compile: [cesiumlang.org/spec/s0-grammar](https://cesiumlang.org/spec/s0-grammar) (EBNF; every production cites its decision). Section 3.10 lists where stage 0 as implemented differs.
2. **The specification draft:** [cesiumlang.org/spec](https://cesiumlang.org/spec/) (the introduction explains the Decided / Provisional / Open markers; chapter 2 is the lexical structure). Only rules marked Decided are settled.
3. **Decision records** in [cesiumlang/cesium](https://github.com/cesiumlang/cesium/issues?q=label%3Adecision) (label `decision`): the ownership design (#11), stage 0 and S0 (#9), core MIR (#8). Open questions have the label `design` or `audit`: never treat their suggestions as decided.
4. **The reference pages:** [cesiumlang.org/reference](https://cesiumlang.org/reference/). They teach by example; their "Open" callouts mark what is undecided.

The pages of cesiumlang.org are written in [cesiumlang/cesiumlang.org](https://github.com/cesiumlang/cesiumlang.org) (`content/spec/`, `content/reference/`).

What stage 0 rejects because the design is open (literals with no typed context, unary minus, hexadecimal and other literal forms, shadowing, `null`, full-Cesium keywords as names, whole-struct assignment) is listed in `bootstrap/README.md` of [cesiumlang/cesium](https://github.com/cesiumlang/cesium), "Open questions stage 0 refuses to answer".

## Examples that compile

In [cesiumlang/cesium](https://github.com/cesiumlang/cesium):

- `bootstrap/tests/s0/*.csm`: S0 programs with their expected output; `bootstrap/tests/s0/errors/` holds programs that must be rejected, with the message.
- `bootstrap/stage1/*.csm`: `cesium1`, about 3,400 lines of S0, the largest Cesium program there is.

## Checking code

- Build the compilers from a clone of cesiumlang/cesium: `python tools/fetch-devkit.py`, then `.devkit/zig/zig build` installs `cesium0` and `cesium1` to `zig-out/bin`.
- `cesium0 --emit-mir -o out.mir a.csm b.csm` checks S0 and reports every error as `file:line:col: error: message` (see the bootstrap README for the exact form).
- `cat a.csm b.csm | cesium1` checks the same unit and stops at the first error; its line numbers count from the start of the joined input.
- With this plugin's language server, `zcsls`, on the `PATH` and a compiler on the `PATH` too, the errors come back as diagnostics after every edit of a `.csm` file.
- A Cesium change is not done until a compiler accepts it, or rejects it with the expected message for an error test.
