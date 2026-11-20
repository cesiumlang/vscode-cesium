# Cesium for Visual Studio Code

The Visual Studio Code extension for the [Cesium programming language](https://cesiumlang.org).

## Features

- The language `cesium` for `.csm` source files and `.csi` module interface files.
- Syntax highlighting with the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar).
- Comments (`//` and `/* */`), bracket matching, auto-closing quotes and brackets, and indentation after an opening bracket.

There is no language server yet: no diagnostics, outline or go to definition. They come with `zcsls`, a stopgap server in Zig in this repository ([#7](https://github.com/cesiumlang/vscode-cesium/issues/7)), until the compiler's own `cesium lsp` takes its place ([cesiumlang/cesium#68](https://github.com/cesiumlang/cesium/issues/68)).

## Status

The language is still being designed, and the extension follows the recorded decisions. Nothing is published to the Visual Studio Marketplace or to Open VSX yet ([#4](https://github.com/cesiumlang/vscode-cesium/issues/4); see [Publishing](#publishing)); to try it, build the VSIX as below and install it with **Extensions: Install from VSIX...**.

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

### Publishing

Each release is published, as `cesiumlang.cesium`, on the GitHub releases page, on the [Visual Studio Marketplace](https://marketplace.visualstudio.com/vscode) and on [Open VSX](https://open-vsx.org) (for VSCodium and other VS Code derivatives), and nowhere else ([#4](https://github.com/cesiumlang/vscode-cesium/issues/4)). While the server is `zcsls`, every release is a pre-release on all three. No stored token is needed: each registry has its own workflow, which the release job of `ci.yml` starts with the released version and which takes the packages from the GitHub release.

- **Marketplace** (`.github/workflows/marketplace.yml`, "Publish to the Marketplace"): `vsce publish --oidc --pre-release`, Marketplace Trusted Publishing. The publisher's Trusted Publishing policy names this repository and that workflow file, and the workflow's GitHub OIDC token is exchanged for a short-lived credential. If that is refused, it falls back, with a warning, to a Microsoft Entra managed identity that is a member of the publisher (`--azure-credential`; the repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`). The universal VSIX goes to the Marketplace, which serves it to the platforms without a package of their own.
- **Open VSX** (`.github/workflows/open-vsx.yml`, "Publish to Open VSX"): `ovsx publish --trusted-publishing`. Open VSX trusts that workflow by its file name for the namespace `cesiumlang`. If that is refused, the repository secret `OVSX_PAT` is used, with a warning. As in zfls, Open VSX gets the platform packages; until there are any (`zcsls`, [#7](https://github.com/cesiumlang/vscode-cesium/issues/7)) it gets the universal VSIX. The packages are marked as pre-releases when they are made, which is what Open VSX reads (ovsx ignores `--pre-release` for a packaged VSIX).
- Either workflow can be run by hand on `main` (Actions, then Run workflow) for any released version; versions already published are skipped (`--skip-duplicate`), so a failed run can simply be run again.
- **Marketplace identity** (`.github/workflows/marketplace-identity.yml`): run by hand once, on `main`, to set up the fallback identity; it signs in as the managed identity of the `AZURE_*` variables and prints the ID to add to the publisher.
- The release notes are generated from the pull requests merged since the last release, in sections by label (`.github/release.yml`): `fix` or `bug`, `feature` or `enhancement`, `performance`, `tests`, `refactor` and `ci`. `skip-changelog` leaves a pull request out, for example the `dev` to `main` pull request of a release.

#### What already exists (checked 2026-11-20)

- **Marketplace publisher `cesiumlang`**, display name "Cesium Language", verified. zfls publishes under it (`cesiumlang.zfls`).
- **Open VSX namespace `cesiumlang`**, verified. zfls publishes under it.
- **The name `cesiumlang.cesium` is free** on both registries. Neither registry reserves an extension name ahead of time: the first publication creates the extension, and from then on its identifier cannot change.

So nothing is registered from scratch. What this repository needs is trust on both registries, because each trust names the repository and the workflow file, and the existing entries name zfls.

#### Setup in the registries

These steps are in the registries' and Azure's web interfaces, signed in with the account that manages the publisher and the namespace. Each is needed once for this repository.

**Visual Studio Marketplace** (publisher management page of `cesiumlang`)

- **Trusted Publishing policy** for the GitHub repository `cesiumlang/vscode-cesium` and the workflow file `marketplace.yml`. The policy for zfls names zfls's repository and does not cover this one. With it, `vsce publish --oidc` exchanges the workflow's GitHub OIDC token for a short-lived credential; nothing is stored.
- **Fallback identity**, used only if Trusted Publishing is refused: in Azure, add a federated credential for this repository (its `main` branch, as zfls's trusts zfls's `main`) to the Microsoft Entra managed identity, or create one for it. Set the repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` here. Then run the "Marketplace identity" workflow once on `main`; it prints the ID to add to the publisher as a member with the Contributor role. If zfls's identity is reused, it is already a member and only the federated credential and the variables are new.

**Open VSX** (namespace `cesiumlang`)

- **Trusted publishing** for this repository's workflow `open-vsx.yml` in the namespace `cesiumlang`. With it, `ovsx publish --trusted-publishing` uses the workflow's OIDC token; nothing is stored.
- **Fallback token**, optional: an Open VSX access token as the repository secret `OVSX_PAT`, used only if trusted publishing is refused. The zfls one can be reused.

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
