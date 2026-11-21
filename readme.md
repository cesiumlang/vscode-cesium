# Cesium for Visual Studio Code

The Visual Studio Code extension for the [Cesium programming language](https://cesiumlang.org).

## Features

- The language `cesium` for `.csm` source files and `.csi` module interface files.
- Syntax highlighting with the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar).
- Comments (`//` and `/* */`), bracket matching, auto-closing quotes and brackets, and indentation after an opening bracket.

The language server is `zcsls`, a stopgap server in Zig in this repository ([#7](https://github.com/cesiumlang/vscode-cesium/issues/7)), until the compiler's own `cesium lsp` takes its place ([cesiumlang/cesium#68](https://github.com/cesiumlang/cesium/issues/68)). So far it reports the errors of the bootstrap compilers (see [zcsls](#zcsls)). Outline, go to definition and the rest come later.

## The language client

The extension starts the language server when a Cesium file is opened, as a thin client ([#2](https://github.com/cesiumlang/vscode-cesium/issues/2)); everything another editor could use is in the server.

- **Finding the server:** the setting `cesium.server.path`, else the `zcsls` bundled in the extension's `bin/` (the platform packages), else `zcsls` on the `PATH`. When there is none, it says so and offers to open the setting. When `cesium lsp` replaces `zcsls`, only the command it starts changes.
- **Settings:** `cesium.server.path` (the server), `cesium.compiler.path` (the compiler it checks with), `cesium.diagnosticsChangeDelay` (for other editors; VS Code pulls diagnostics as you type) and `cesium.trace.server` (log the protocol messages). The client passes the `cesium` settings to the server as they are, at start-up and whenever they change (`workspace/didChangeConfiguration`), and the server applies them without a restart and resolves their paths; only a change of `cesium.server.path` restarts the server.
- **Command:** **Cesium: Restart Language Server** (`cesium.restartServer`).
- **Output:** the output channel "Cesium Language Server" has the client's log and the server's.
- **Untrusted workspaces:** supported, but the workspace's values of `cesium.server.path` and `cesium.compiler.path`, which name programs to run, are ignored there. **Virtual workspaces:** highlighting only; the server reads files from disk, so it serves files and untitled documents only.

## `zcsls`

`zcsls` (`server/`) speaks the Language Server Protocol over standard input and output, and every feature works through standard LSP, so any editor can use it (see [Other editors](#other-editors)). The requests it answers are those `cesium lsp` must answer later: `initialize`, `initialized`, `shutdown`, `exit`, full text sync (`textDocument/didOpen`, `didChange`, `didSave`, `didClose`), `textDocument/diagnostic`, `workspace/didChangeConfiguration` and `workspace/didChangeWatchedFiles`; it sends `textDocument/publishDiagnostics`, and asks the client `client/registerCapability` and `workspace/diagnostic/refresh`. It has no custom requests or notifications. The name is temporary: settings and commands are `cesium.*`.

- **Settings.** `compiler.path` and `diagnosticsChangeDelay`, the names of the editor's settings without `cesium.`, as zfls takes its own: in the `initializationOptions` of `initialize` and in `workspace/didChangeConfiguration`, either as one object (`{"compiler": {"path": "..."}}`) or in its `cesium` member (`{"cesium": {"compiler": {"path": "..."}}}`, as VS Code sends them). A setting left out keeps its value, and `null` restores its default. A change applies at once, without a restart: a new `compiler.path` finds the compiler again and checks the open documents' units again (a client that pulls diagnostics is asked to pull them again); a new `diagnosticsChangeDelay` applies from the next change. Path settings may start with `~` (the home directory), and a relative one is taken relative to the workspace's root (`rootUri`, else the first workspace folder).
- **The compiler.** It checks with `cesium1` when there is one, since it follows S1 as it grows, else with `cesium0`, which knows only S0 (see `bootstrap/README.md` in [cesiumlang/cesium](https://github.com/cesiumlang/cesium)). `compiler.path` names a compiler or a directory that holds one; without it, `cesium1` and then `cesium0` are looked for on the `PATH`. A compiler whose name starts with `cesium0` is run as `cesium0`, any other as `cesium1`. No compiler is bundled: in cesium-workspace they are built in `../cesium-src`, where `zig build` installs both to `zig-out/bin`.
- **The unit.** What files make a compilation unit is not decided yet ([#7](https://github.com/cesiumlang/vscode-cesium/issues/7)). Until it is, the unit of a file is every `.csm` file in its directory, in byte order of their names (`server/unit.zig`, the one place to change).
- **Diagnostics, pulled.** A client that pulls diagnostics (its `textDocument.diagnostic` capability, as VS Code's has) gets `diagnosticProvider` with `interFileDependencies`, and asks for them (`textDocument/diagnostic`); each pull checks the document's unit, unless nothing changed since the last check, and a pull with the last `resultId` gets `unchanged` report. The unit's other open documents get their reports from the same check when they are pulled. Its files that are not open are not pulled, so their diagnostics are published, as to other clients; once such a file is opened, what was published of it is cleared and is pulled.
- **Diagnostics, published.** To another client, the unit is checked when a document is opened and when it is saved, and after a change once the text has not changed for `diagnosticsChangeDelay` milliseconds (300 by default, as zfls's): a burst of typing costs one check, of the last text. 0 checks with each change, a negative value only on open and save. Each file of the unit gets its diagnostics, and a later check clears those that are gone.
- **Files changed on disk.** Where the client allows it (`workspace.didChangeWatchedFiles.dynamicRegistration`), `zcsls` asks it at `initialized` to watch `**/*.{csm,csi}`. A file created, changed or deleted outside the editor checks the units of the open documents it belongs to again (or asks for a pull); a deleted file's diagnostics are cleared. An open document is left alone, its text being the editor's.
- **What the compilers read.** `cesium1` reads the unit on standard input, so it is given the text of the open documents, unsaved edits included; `cesium0` reads files, so it sees what is saved, and only a save changes what it finds. A document that is not a local file (an untitled one) is a unit of its own, checked by `cesium1` only.
- **Where errors go.** `cesium1` counts lines from the start of its input, the unit's files one after another (each ending in a line break); `zcsls` maps each line back to its file and line. `cesium0` names the file. Columns are converted to UTF-16, as LSP counts them. A message without a place (the verifier's, a limit of `cesium1`) goes on the first line of the document checked.
- **Limits.** `cesium1` stops at the first error, so a unit shows one error at a time; `cesium0` reports every error it finds, but knows only S0. An error at the end of one file can be reported at the start of the next one, as the compiler sees them joined. A check runs while the server waits, so a slow compiler delays the answers that follow (it is stopped after 30 seconds).
- `zcsls --version` prints its version, which is the extension's (`build.zig.zon`).

## Other editors

`zcsls` comes only inside the pre-release platform packages of this extension, in their `bin/` (see [Agent plugin](#agent-plugin) for where VS Code unpacks them), or from building this repository (`zig build` puts it in `zig-out/bin`); there are no separate downloads until `cesium lsp` replaces it. Any LSP client starts it with no arguments and talks to it over standard input and output; the settings are those of [`zcsls`](#zcsls). In Neovim (0.11 or later), for instance:

```lua
vim.filetype.add({ extension = { csm = "cesium", csi = "cesium" } })
vim.lsp.config("zcsls", {
  cmd = { "zcsls" },
  filetypes = { "cesium" },
  root_markers = { ".git" },
  init_options = { compiler = { path = "~/cesium/zig-out/bin" } },
  settings = { cesium = { diagnosticsChangeDelay = 500 } },
})
vim.lsp.enable("zcsls")
```

`init_options` are read at start-up; `settings` are sent with `workspace/didChangeConfiguration`, and a change to them applies without a restart. Without a compiler setting, `zcsls` looks for `cesium1`, then `cesium0`, on the `PATH` of the editor. There are no custom requests to wire up: diagnostics come by pull where the client pulls them and are published otherwise.

## Agent plugin

`agent-plugin/` is a plugin for [Claude Code](https://code.claude.com/docs/en/plugins/code-intelligence) ([#21](https://github.com/cesiumlang/vscode-cesium/issues/21)). It makes `zcsls` the language server of `.csm` and `.csi` files, so an agent gets the compiler's errors after each edit, and it adds the skill `cesium-language`: where the rules of Cesium are written down and how to check code. `.claude-plugin/marketplace.json` makes this repository its marketplace:

```sh
claude plugin marketplace add cesiumlang/vscode-cesium
claude plugin install cesium@cesiumlang
```

- **`zcsls` on the `PATH`.** The plugin does not carry the server: Claude Code starts `zcsls` from the `PATH` of the shell it runs in. `zcsls` comes only inside the platform packages of this extension, in their `bin/`; there are no separate downloads until `cesium lsp` replaces it. Put that directory on the `PATH` before starting Claude Code. It is in VS Code's extensions folder (`~/.vscode/extensions`, `%USERPROFILE%\.vscode\extensions` on Windows, `~/.vscode-insiders/extensions` for Insiders), in a folder named `cesiumlang.cesium-<version>-<platform>`, which changes with every update; these lines pick the newest one:

  ```sh
  export PATH="$(ls -td ~/.vscode/extensions/cesiumlang.vscode-cesium-*/bin | head -n 1):$PATH"
  ```

  ```powershell
  $env:PATH = (Get-ChildItem "$HOME\.vscode\extensions\cesiumlang.vscode-cesium-*\bin" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName + ";$env:PATH"
  ```

  Or build it: `zig build` here puts it in `zig-out/bin`.
- **A compiler on the `PATH`.** Claude Code starts `zcsls` without `initializationOptions`, so it looks for `cesium1`, then `cesium0`, on the same `PATH` (see [zcsls](#zcsls)). Build them from [cesiumlang/cesium](https://github.com/cesiumlang/cesium) (`zig build` installs both to `zig-out/bin`) and put that directory on the `PATH` too. Without a compiler, `zcsls` runs but has no diagnostics.
- **What it gives.** Diagnostics after each edit. `zcsls` does not answer definitions, references, hover or symbols yet, so Claude Code's LSP tool has nothing for those.
- **Limits.** Language servers do not run in Claude Code's cloud sessions. In VS Code, Claude Code reads the Problems panel, where the extension's `zcsls` reports already; the plugin matters most for terminal and background agents.
- **Copilot:** not yet. Copilot CLI reads the language servers of an Agent Plugins 1.0 plugin from `com.github.copilot/lsp.json`, whose contents its documentation does not define yet (checked 2026-11-20).
- **Checks.** `claude plugin validate` does not read `.lsp.json`. `npm run unit` (`test/unit/plugin.test.ts`, in CI) checks that the plugin's JSON files parse, that the marketplace finds the plugin under its name, that `.lsp.json` starts `zcsls` for `.csm` and `.csi` as the language `cesium` of `package.json`, and that each skill has a name and a description.
- The skill is the `cesium-language` skill of cesium-workspace with links in place of the workspace's paths. It gives way to the reference that cesiumlang/cesiumlang.org#25 generates, once there is one.

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
- `npm test` runs `test/suite.ts` in a VS Code that `@vscode/test-electron` downloads, on the files of `test/fixture/`: the extension activates and `.csm` and `.csi` files are the language `cesium`. `CESIUM_EXTENSION_PATH` names an unpacked VSIX (its `extension` directory) to test instead of the checkout. With `CESIUM_DIAGNOSTICS` set, it also opens `test/fixture/error/unknown_name.csm` and waits for the language server's diagnostic, which needs `zcsls` (a platform VSIX, or `cesium.server.path`) and `cesium1` on the `PATH`. CI builds `cesium1` from cesiumlang/cesium `dev` for that, and skips this part with a warning if it cannot.
- `zig build` builds `zcsls` into `zig-out/bin`.
- `zig build package-vscode -- DIST` writes `DIST/vscode-cesium-v<version>-<platform>.vsix` (`build/package_vscode.zig`), as in zfls: one per VS Code platform (`win32-x64`, `win32-arm64`, `linux-x64`, `linux-arm64`, `alpine-x64`, `alpine-arm64`, `darwin-x64`, `darwin-arm64`), each with `zcsls` cross-compiled for it in `bin/`, and `universal` without a server. `-Dplatforms=false` packages the universal VSIX only.
- `zig build test` runs the unit tests of `zcsls` (`server/`, `server/_test/`) and of the build tools in `build/`, and the LSP test (`server/_test/lsp_test.zig`): the built `zcsls` driven as a plain LSP client drives it, with a stand-in for `cesium1` (`server/_test/fake_cesium1.zig`), as a client that pulls diagnostics and as one that does not (initialize, a unit with an error, diagnostics by pull and by push, a change of the settings, files changed on disk, shutdown). CI runs `zig build test` on Linux, macOS and Windows.
- `.vscodeignore` lists what goes into the VSIX, and nothing else does.
- **Supported VS Code:** `engines.vscode` is the stable VS Code that was current when it was last raised (1.147.0, 2026-11-20). No compatibility with older versions is kept: raise it whenever a newer API or Node.js helps. `@types/vscode` is the newest published version not above it (1.146.0; the types trail a release), and `@types/node` and esbuild's target follow that VS Code's Node.js (24).
- Dependencies are pinned to exact versions and kept free of `npm audit` findings.
- `overrides` in `package.json` forces `minimatch` 11.0.9: `@vscode/vsce` 4.1.1 asks for `^10.2.6`, which has [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249) (fixed in 11.0.1). Drop the override once `@vscode/vsce` depends on a fixed version.

### Versions and releases

- `build.zig.zon` holds the version of the next release; packaging writes it into `package.json` for the VSIX only, so the version in `package.json` is a placeholder (`0.0.0`).
- While the server is `zcsls`, every version is a pre-release, `0.<odd>.<patch>` ([#3](https://github.com/cesiumlang/vscode-cesium/issues/3)): the Marketplace takes no semver suffixes such as `-pre` and recommends odd minor versions for pre-releases. Packaging fails on a version with an even minor, and marks the VSIX as a pre-release. The first full release comes with `cesium lsp`.
- GitHub Actions (`.github/workflows/ci.yml`) builds, tests and packages every pull request and every push to `main` and `dev`: the type check, the unit tests, the generated files, the VSIX files, and each runner's platform VSIX run in a downloaded VS Code on Linux, macOS and Windows. Its job "CI" sums up a run, for the rulesets to require.
- A push to `main` whose version is not tagged yet is released once it passes: the commit is tagged, a GitHub pre-release is made with the VSIX, the publishing workflows are started, and `main` is merged back into `dev`, where `build.zig.zon` gets the next patch version. For a new minor version, set it on `dev` by hand. A pull request into `main` fails when its version is already released.

### Publishing

Each release is published, as `cesiumlang.vscode-cesium`, on the GitHub releases page, on the [Visual Studio Marketplace](https://marketplace.visualstudio.com/vscode) and on [Open VSX](https://open-vsx.org) (for VSCodium and other VS Code derivatives), and nowhere else ([#4](https://github.com/cesiumlang/vscode-cesium/issues/4)). While the server is `zcsls`, every release is a pre-release on all three. No stored token is needed: each registry has its own workflow, which the release job of `ci.yml` starts with the released version and which takes the packages from the GitHub release.

- **Marketplace** (`.github/workflows/marketplace.yml`, "Publish to the Marketplace"): `vsce publish --oidc --pre-release`, Marketplace Trusted Publishing. The publisher's Trusted Publishing policy names this repository and that workflow file, and the workflow's GitHub OIDC token is exchanged for a short-lived credential. If that is refused, it falls back, with a warning, to a Microsoft Entra managed identity that is a member of the publisher (`--azure-credential`; the repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`). The universal VSIX goes to the Marketplace, which serves it to the platforms without a package of their own.
- **Open VSX** (`.github/workflows/open-vsx.yml`, "Publish to Open VSX"): `ovsx publish --trusted-publishing`. Open VSX trusts that workflow by its file name for the namespace `cesiumlang`. If that is refused, the repository secret `OVSX_PAT` is used, with a warning. As in zfls, Open VSX gets the platform packages; until there are any (`zcsls`, [#7](https://github.com/cesiumlang/vscode-cesium/issues/7)) it gets the universal VSIX. The packages are marked as pre-releases when they are made, which is what Open VSX reads (ovsx ignores `--pre-release` for a packaged VSIX).
- Either workflow can be run by hand on `main` (Actions, then Run workflow) for any released version; versions already published are skipped (`--skip-duplicate`), so a failed run can simply be run again.
- **Marketplace identity** (`.github/workflows/marketplace-identity.yml`): run by hand once, on `main`, to set up the fallback identity; it signs in as the managed identity of the `AZURE_*` variables and prints the ID to add to the publisher.
- The release notes are generated from the pull requests merged since the last release, in sections by label (`.github/release.yml`): `fix` or `bug`, `feature` or `enhancement`, `performance`, `tests`, `refactor` and `ci`. `skip-changelog` leaves a pull request out, for example the `dev` to `main` pull request of a release.

#### Setup in the registries

The Marketplace publisher `cesiumlang` (display name "Cesium Language") and the Open VSX namespace `cesiumlang` already exist and are verified; zfls publishes under both. The first publication of `cesiumlang.vscode-cesium` creates the extension, and its identifier cannot change after that. Trust names this repository and the workflow file, so the entries of zfls do not cover it, and trusted publishing can be set up only for an extension that exists. The order is therefore:

1. **The first release** (`v0.1.0`, a push to `main`) creates the GitHub pre-release with every VSIX and starts both publishing workflows.
2. **Open VSX:** the first run falls back to the repository secret `OVSX_PAT` (an Open VSX access token; set on 2026-11-20), which creates the extension. Then allow trusted publishing for `open-vsx.yml` in the namespace `cesiumlang`; the secret stays as the fallback only.
3. **Marketplace:** a Trusted Publishing policy for this repository and `marketplace.yml` exists on the publisher (set on 2026-11-20). If the Marketplace still refuses because the extension does not exist yet, upload the release's own universal VSIX on the publisher page (New extension, Visual Studio Code), then run the workflow again for the platform packages. Upload nothing built elsewhere: a version that is already published is skipped, so the release's contents would not be published under it.
4. **Fallback identity** for the Marketplace, optional, used only if Trusted Publishing is refused: in Azure, add a federated credential for this repository (its `main` branch) to the Microsoft Entra managed identity, set the repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`, and run the "Marketplace identity" workflow once on `main`; it prints the ID to add to the publisher as a member with the Contributor role.

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
