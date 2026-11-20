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

The extension is TypeScript, bundled with esbuild. Node.js is the version in `.node-version`, which the `.envrc` selects through [fnm](https://github.com/Schniz/fnm) when [direnv](https://direnv.net) is installed. The build steps are Zig, as in zfls, with the Zig of the Cesium devkit (the version in `devkit-version`): in cesium-workspace that is `../cesium-src/.devkit/zig/zig` (`python tools/fetch-devkit.py` in `cesium-src`), which the `.envrc` puts on the `PATH`.

```sh
git submodule update --init
npm ci
npm run typecheck
npm run unit
zig build test
zig build package-vscode -- dist
npm test   # in a downloaded VS Code
```

- `npm run build` bundles `src/` into `dist/extension.js`; packaging runs it first.
- `npm run unit` runs the tests in `test/unit/` with plain Node.js, without VS Code.
- `npm test` runs `test/suite.ts` in a VS Code that `@vscode/test-electron` downloads, on the files of `test/fixture/`: the extension activates and `.csm` and `.csi` files are the language `cesium`. `CESIUM_EXTENSION_PATH` names an unpacked VSIX (its `extension` directory) to test instead of the checkout.
- `zig build package-vscode -- DIST` writes `DIST/vscode-cesium-v<version>-universal.vsix` (`build/package_vscode.zig`). Until `zcsls` exists ([#7](https://github.com/cesiumlang/vscode-cesium/issues/7)) there is no server to bundle, so the universal VSIX is the only one; with `zcsls`, one VSIX per VS Code platform with its `zcsls` in `bin/` is added, as in zfls.
- `zig build test` runs the unit tests of the build tools in `build/`.
- `.vscodeignore` lists what goes into the VSIX, and nothing else does.
- **Supported VS Code:** `engines.vscode` is the stable VS Code that was current when it was last raised (1.147.0, 2026-11-20). No compatibility with older versions is kept: raise it whenever a newer API or Node.js helps. `@types/vscode` is the newest published version not above it (1.146.0; the types trail a release), and `@types/node` and esbuild's target follow that VS Code's Node.js (24).
- Dependencies are pinned to exact versions and kept free of `npm audit` findings.
- `overrides` in `package.json` forces `minimatch` 11.0.9: `@vscode/vsce` 4.1.1 asks for `^10.2.6`, which has [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249) (fixed in 11.0.1). Drop the override once `@vscode/vsce` depends on a fixed version.

### Versions and releases

- `build.zig.zon` holds the version of the next release; packaging writes it into `package.json` for the VSIX only, so the version in `package.json` is a placeholder (`0.0.0`).
- While the server is `zcsls`, every version is a pre-release, `0.<odd>.<patch>` ([#3](https://github.com/cesiumlang/vscode-cesium/issues/3)): the Marketplace takes no semver suffixes such as `-pre` and recommends odd minor versions for pre-releases. Packaging fails on a version with an even minor, and marks the VSIX as a pre-release. The first full release comes with `cesium lsp`.
- GitHub Actions (`.github/workflows/ci.yml`) builds, tests and packages every pull request and every push to `main` and `dev`: the type check, the unit tests, the generated files, the VSIX, and the VSIX run in a downloaded VS Code on Linux, macOS and Windows. Its job "CI" sums up a run, for the rulesets to require.
- A push to `main` whose version is not tagged yet is released once it passes: the commit is tagged, a GitHub pre-release is made with the VSIX, the publishing workflows are started, and `main` is merged back into `dev`, where `build.zig.zon` gets the next patch version. For a new minor version, set it on `dev` by hand. A pull request into `main` fails when its version is already released.

### Where the files come from

| Path | Source |
| --- | --- |
| `grammar/` | The submodule [cesiumlang/grammar](https://github.com/cesiumlang/grammar), branch `dev`; only `cesium.tmGrammar.json` and its license go into the VSIX |
| `icons/cesium.png`, `icons/cesium.svg` | The website's logo, `content/assets/cesium_logo.png` and `cesium_logo.svg` of [cesiumlang.org](https://github.com/cesiumlang/cesiumlang.org), copied unchanged; the PNG is the extension's icon, the SVG the file icon of the language |

### Translations

The extension is in English only, with the hooks for translations in place, as in [zfls](https://github.com/cesiumlang/zfls).

- Every string of `package.json` that VS Code shows is a `%key%` there, whose English text is in `package.nls.json`. A translation is a `package.nls.<language>.json` with the same keys.
- Messages shown while the extension runs are written with `vscode.l10n.t("...")`, with a string literal, and listed in `l10n/bundle.l10n.json` (there are none yet). A translation is `l10n/bundle.l10n.<language>.json`.
- `zig build generated` writes both from the sources (`build/generated.zig`, from zfls): it moves new strings of `package.json` into `package.nls.json` and lists the `vscode.l10n.t` messages of `src/` in the bundle. `zig build check-generated`, run by CI, fails when either is out of date.
- The unit tests check that every key is in `package.nls.json` and that a translation has no other keys.

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
