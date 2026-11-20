// Finding the language server's executable and resolving the paths of the
// settings, as zfls does. No `vscode` import, so that plain Node.js unit
// tests can load this module.

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/** The server's name while it is the bootstrap server of #7 */
export const SERVER_NAME = "zcsls";

/**
 * A path setting as a path: a leading `~` is the home directory, and a
 * relative path is taken relative to `base` (the first workspace folder)
 * when there is one. Empty when the setting is.
 */
export function resolveSetting(value: string, base?: string, home = os.homedir()): string {
  const v = value.trim();
  if (!v) {
    return "";
  }
  if (v === "~") {
    return home;
  }
  if (v.startsWith("~/") || v.startsWith("~\\")) {
    return path.join(home, v.slice(2));
  }
  return path.isAbsolute(v) || !base ? v : path.resolve(base, v);
}

export interface Found {
  /** The executable to start */
  command?: string;
  /** Where it was looked for in vain: what the setting names */
  tried?: string;
}

/**
 * The server to start: the one `configured` (`cesium.server.path`, resolved)
 * names, else the one bundled in `bundledDir` (the extension's `bin/`), else
 * the one on the PATH.
 */
export function findServer(
  configured: string,
  bundledDir: string,
  env: NodeJS.ProcessEnv = process.env,
): Found {
  if (configured) {
    return isFile(configured) ? { command: configured } : { tried: configured };
  }
  const exe = process.platform === "win32" ? `${SERVER_NAME}.exe` : SERVER_NAME;
  const bundled = path.join(bundledDir, exe);
  if (isFile(bundled)) {
    return { command: bundled };
  }
  const pathVar = Object.keys(env).find((k) => k.toUpperCase() === "PATH");
  for (const dir of (pathVar ? (env[pathVar] ?? "") : "").split(path.delimiter)) {
    const candidate = dir && path.join(dir, exe);
    if (candidate && isFile(candidate)) {
      return { command: candidate };
    }
  }
  return {};
}

/** Restores the executable bit of `file` should unpacking have dropped it */
export function ensureExecutable(file: string): void {
  if (process.platform === "win32") {
    return;
  }
  try {
    fs.accessSync(file, fs.constants.X_OK);
  } catch {
    fs.chmodSync(file, 0o755);
  }
}

function isFile(file: string): boolean {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}
