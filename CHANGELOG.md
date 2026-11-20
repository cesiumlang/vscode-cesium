# Changelog

## 0.1.0 (unreleased)

- The language `cesium` for `.csm` and `.csi` files, with the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar).
- Comments, brackets, auto-closing pairs and indentation rules.
- The logo of [cesiumlang.org](https://cesiumlang.org) as the extension's icon and the file icon of the language.
- `zcsls`, a bootstrap language server in Zig: diagnostics from `cesium1` or `cesium0` on the unit of a file, on open and on save. The platform packages carry it in `bin/`.
- The language client: it starts `zcsls` (`cesium.server.path`, the bundled one, or the `PATH`) for Cesium files, restarts it when its settings change or with **Cesium: Restart Language Server**, and logs to the output channel "Cesium Language Server". The setting `cesium.compiler.path` names the bootstrap compiler.
