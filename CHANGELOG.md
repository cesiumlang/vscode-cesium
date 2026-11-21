# Changelog

## 0.1.0 (unreleased)

- The language `cesium` for `.csm` and `.csi` files, with the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar).
- Comments, brackets, auto-closing pairs and indentation rules.
- The logo of [cesiumlang.org](https://cesiumlang.org) as the extension's icon and the file icon of the language.
- `zcsls`, a bootstrap language server in Zig: diagnostics from `cesium1` or `cesium0` on the unit of a file, pulled by the editor (`textDocument/diagnostic`) or published on open, on save and after a pause in typing (`cesium.diagnosticsChangeDelay`). It takes its settings over LSP (`initializationOptions`, `workspace/didChangeConfiguration`) without a restart and checks again when Cesium files change on disk (`workspace/didChangeWatchedFiles`), for any LSP client. The platform packages carry it in `bin/`.
- The language client: it starts `zcsls` (`cesium.server.path`, the bundled one, or the `PATH`) for Cesium files, sends it the `cesium.*` settings when they change, restarts it when `cesium.server.path` changes or with **Cesium: Restart Language Server**, and logs to the output channel "Cesium Language Server". The setting `cesium.compiler.path` names the bootstrap compiler.
