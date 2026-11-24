---
applyTo: "**/*.csm,**/*.csi"
---

# Cesium files

This is Cesium source. No model was trained on Cesium: do not guess its syntax from C, Zig or C++.

- The rules of the language, with where each comes from and what is still open, are in the skill `cesium-language`; read it before writing or changing Cesium code.
- Check every change with the language server (`zcsls`, whose errors are in the Problems panel) or a compiler (`cesium0`, `cesium1`). A change is not done until a compiler accepts it, or rejects it with the expected message for an error test.
- Where the skill says a point is open, say so; never invent a rule.
