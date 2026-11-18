# Cesium for Visual Studio Code

The Visual Studio Code extension for the [Cesium programming language](https://cesiumlang.org).

## Status

There is no extension yet. This repository exists so that the work has a place, and its [issues](https://github.com/cesiumlang/vscode-cesium/issues) list what is to be built. Nothing is published to the Visual Studio Marketplace or to Open VSX.

## Plan

- The extension is a thin client. The `cesium` compiler is one executable that also contains the language server ([cesiumlang/cesium#2](https://github.com/cesiumlang/cesium/issues/2)); the extension starts it and speaks the Language Server Protocol with it.
- Syntax highlighting comes from the TextMate grammar of [cesiumlang/grammar](https://github.com/cesiumlang/grammar), for `.csm` source files and `.csi` module interface files.
- The build, the packaging per platform and the publishing follow [zfls](https://github.com/cesiumlang/zfls), the organization's other extension, which already publishes to both registries without stored tokens.

## Related repositories

| Repository | What |
| --- | --- |
| [cesium](https://github.com/cesiumlang/cesium) | The compiler, which contains the language server |
| [cesium-workspace](https://github.com/cesiumlang/cesium-workspace) | The workspace that has this repository, the compiler and the others as submodules side by side |
| [grammar](https://github.com/cesiumlang/grammar) | The TextMate grammar and its tests |
| [zfls](https://github.com/cesiumlang/zfls) | The model for the extension's build and release pipeline (`editors/vscode` and `.github/workflows` there) |

## Development setup

Nothing to build yet. The repository already carries the organization's usual files: `.node-version` and an `.envrc` for [direnv](https://direnv.net) that selects that Node.js version through [fnm](https://github.com/Schniz/fnm), and a workspace file for VS Code.

## Branches

Work goes to `dev` through pull requests, and `dev` goes to `main` through a pull request.

## License

[MIT](LICENSE)
