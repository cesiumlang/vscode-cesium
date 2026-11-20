# Cesium for Visual Studio Code

The Visual Studio Code extension for the [Cesium programming language](https://cesiumlang.org).

## Features

- The language `cesium` for `.csm` source files and `.csi` module interface files.
- Syntax highlighting with the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar).
- Comments (`//` and `/* */`), bracket matching, auto-closing quotes and brackets, and indentation after an opening bracket.

There is no language server yet: no diagnostics, outline or go to definition. They come with `zcsls`, a stopgap server in Zig in this repository ([#7](https://github.com/cesiumlang/vscode-cesium/issues/7)), until the compiler's own `cesium lsp` takes its place ([cesiumlang/cesium#68](https://github.com/cesiumlang/cesium/issues/68)).

## Status

The language is still being designed, and the extension follows the recorded decisions. Nothing is published to the Visual Studio Marketplace or to Open VSX yet ([#4](https://github.com/cesiumlang/vscode-cesium/issues/4)); to try it, build the VSIX as below and install it with **Extensions: Install from VSIX...**.

## Development setup

The extension is TypeScript, bundled with esbuild. Node.js is the version in `.node-version`, which the `.envrc` selects through [fnm](https://github.com/Schniz/fnm) when [direnv](https://direnv.net) is installed.

```sh
git submodule update --init
npm ci
npm run typecheck
npm run unit
npx vsce package
```

- `npm run build` bundles `src/` into `dist/extension.js`; `vsce package` runs it first.
- `npm run unit` runs the tests in `test/unit/` with plain Node.js, without VS Code.
- `.vscodeignore` lists what goes into the VSIX, and nothing else does.
- **Supported VS Code:** `engines.vscode` is the stable VS Code that was current when it was last raised (1.147.0, 2026-11-20). No compatibility with older versions is kept: raise it whenever a newer API or Node.js helps. `@types/vscode` is the newest published version not above it (1.146.0; the types trail a release), and `@types/node` and esbuild's target follow that VS Code's Node.js (24).
- Dependencies are pinned to exact versions and kept free of `npm audit` findings.
- `overrides` in `package.json` forces `minimatch` 11.0.9: `@vscode/vsce` 4.1.1 asks for `^10.2.6`, which has [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249) (fixed in 11.0.1). Drop the override once `@vscode/vsce` depends on a fixed version.

### Where the files come from

| Path | Source |
| --- | --- |
| `grammar/` | The submodule [cesiumlang/grammar](https://github.com/cesiumlang/grammar), branch `dev`; only `cesium.tmGrammar.json` and its license go into the VSIX |
| `icons/cesium.png`, `icons/cesium.svg` | The website's logo, `content/assets/cesium_logo.png` and `cesium_logo.svg` of [cesiumlang.org](https://github.com/cesiumlang/cesiumlang.org), copied unchanged; the PNG is the extension's icon, the SVG the file icon of the language |

### Translations

The extension is in English only, with the hooks for translations in place, as in [zfls](https://github.com/cesiumlang/zfls).

- Every string of `package.json` that VS Code shows is a `%key%` there, whose English text is in `package.nls.json`. A translation is a `package.nls.<language>.json` with the same keys.
- Messages shown while the extension runs are written with `vscode.l10n.t("...")` and listed in `l10n/bundle.l10n.json` (there are none yet). A translation is `l10n/bundle.l10n.<language>.json`.
- The unit tests check that every key is in `package.nls.json` and that a translation has no other keys. Generating these files, as zfls does with `zig build generated`, is left for [#3](https://github.com/cesiumlang/vscode-cesium/issues/3).

## Related repositories

| Repository | What |
| --- | --- |
| [cesium](https://github.com/cesiumlang/cesium) | The compiler, which is to contain the language server |
| [cesium-workspace](https://github.com/cesiumlang/cesium-workspace) | The workspace that has this repository, the compiler and the others as submodules side by side |
| [grammar](https://github.com/cesiumlang/grammar) | The TextMate grammar and its tests |
| [zfls](https://github.com/cesiumlang/zfls) | The model for the extension's build and release pipeline (`editors/vscode` and `.github/workflows` there) |

## Branches

Work goes to `dev` through pull requests, and `dev` goes to `main` through a pull request.

## License

[MIT](LICENSE)
