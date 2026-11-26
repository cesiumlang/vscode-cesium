# Changelog

## 0.1.3 (unreleased)

- Breakpoints can be set in `.csm` files, for a native debugger: the bootstrap compilers' output now has line information (cesiumlang/cesium#78), and the readme's "Debugging" gives launch configurations for lldb-dap and gdb, and for the Visual Studio debugger on Windows, where the compilers now write CodeView line tables (#47). In a debug build, the compilers' default, the debugger also shows locals and parameters with their types, in their lexical scopes (cesiumlang/cesium#143).

- `zcsls` reads the compilers' diagnostic codes (`error[E0304]: ...`, cesiumlang/cesium#82) and gives each as its diagnostic's code, shown in the Problems panel with a link to its explanation on cesiumlang.org; without this, compilers that print codes had their errors dropped.

## 0.1.2

- For the AI assistants in VS Code: the Cesium skill (`contributes.chatSkills`), the rules of the language with where each comes from and what is still open, generated from the specification on [cesiumlang.org](https://cesiumlang.org); and instructions for Cesium files (`contributes.chatInstructions`), to read the skill and check every change with the language server or a compiler. The agent plugin ships the same skill.
- The `zcsls.exe` in the Windows packages is signed (Authenticode, through Azure Artifact Signing).

## 0.1.1

- The extension is now `cesiumlang.vscode-cesium`: the Visual Studio Marketplace does not accept a new extension named `cesium`, which another publisher has. The same identifier is used on Open VSX, where `cesiumlang.cesium` 0.1.0 is withdrawn.

## 0.1.0

- The language `cesium` for `.csm` and `.csi` files, with the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar).
- Comments, brackets, auto-closing pairs and indentation rules.
- The logo of [cesiumlang.org](https://cesiumlang.org) as the extension's icon and the file icon of the language.
- `zcsls`, a bootstrap language server in Zig: diagnostics from `cesium1` or `cesium0` on the unit of a file, pulled by the editor (`textDocument/diagnostic`) or published on open, on save and after a pause in typing (`cesium.diagnosticsChangeDelay`). It takes its settings over LSP (`initializationOptions`, `workspace/didChangeConfiguration`) without a restart and checks again when Cesium files change on disk (`workspace/didChangeWatchedFiles`), for any LSP client. The platform packages carry it in `bin/`.
- The language client: it starts `zcsls` (`cesium.server.path`, the bundled one, or the `PATH`) for Cesium files, sends it the `cesium.*` settings when they change, restarts it when `cesium.server.path` changes or with **Cesium: Restart Language Server**, and logs to the output channel "Cesium Language Server". The setting `cesium.compiler.path` names the bootstrap compiler.
