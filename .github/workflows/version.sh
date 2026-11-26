#!/usr/bin/env bash
# version.sh: the extension's version and every place that states it, run
# from the repository root by ci.yml, as skein's version.sh. build.zig.zon
# holds it; package.json and package-lock.json keep the placeholder 0.0.0,
# which package_vscode.zig replaces for packaging only. A new place that
# states the version is added here.
#   version.sh           prints the version; fails, listing the places, when
#                        one is missing or wrong
#   version.sh set NEXT  sets every place to NEXT and opens its changelog
#                        section, as CI does when it begins the next version
set -euo pipefail

zon=build.zig.zon
pkg=package.json
lock=package-lock.json
log=CHANGELOG.md
placeholder=0.0.0

zon_version() { sed -nE 's/^    \.version = "([^"]+)",$/\1/p' "$zon"; }

# places: one "FILE: WANTED GOT" line for each place that states the version
places() {
  local version name
  version=$(zon_version)
  name=$(sed -nE 's/^  "name": "([^"]+)",$/\1/p' "$pkg")
  echo "$zon: $version $version"
  # the first section: the version being made, or on main the one released
  echo "$log: $version $(sed -nE '/^## /{s/^## ([^ ]+)( \(unreleased\))?$/\1/p;q}' "$log")"
  echo "$pkg: $placeholder $(sed -nE 's/^  "version": "([^"]+)",$/\1/p' "$pkg")"
  # the package's own two entries in the lock: the top level and packages[""]
  sed -nE "/^ {2,6}\"name\": \"$name\",$/{n;s/^ +\"version\": \"([^\"]+)\",$/\1/p}" "$lock" | sed "s|^|$lock: $placeholder |"
}

check() {
  local version list
  version=$(zon_version)
  list=$(places)
  if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$(grep -c . <<< "$list")" -ne 5 ] \
    || grep -qvE '^[^:]+: ([^ ]+) \1$' <<< "$list"; then
    echo "version.sh: build.zig.zon's MAJOR.MINOR.PATCH ('$version') in the changelog, $placeholder in $pkg and both entries of $lock (same name as $pkg); found (wanted, got):" >&2
    echo "$list" >&2
    exit 1
  fi
  echo "$version"
}

set_version() {
  local next=$1
  [[ $next =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version.sh: '$next' is not MAJOR.MINOR.PATCH" >&2; exit 1; }
  sed -i -E "s/^(    \.version = \")[^\"]+(\",)$/\1$next\2/" "$zon"
  # a section for NEXT above the others, which are then released
  if [ "$(grep -m1 '^## ' "$log")" != "## $next (unreleased)" ]; then
    { printf '# Changelog\n\n## %s (unreleased)\n\n' "$next"; tail -n +3 "$log" | sed -E 's/^(## .*) \(unreleased\)$/\1/'; } > "$log.new"
    mv "$log.new" "$log"
  fi
  check > /dev/null
}

case "${1:-}" in
  "") check ;;
  set) set_version "${2:?version.sh set NEXT}" ;;
  *) echo "version.sh: [set NEXT]" >&2; exit 1 ;;
esac
