#!/usr/bin/env bash
# Select the newest installed Xcode whose Swift is at least MIN_VERSION and
# export it as DEVELOPER_DIR for later GitHub Actions steps.
#
# The SwiftPM lanes need Swift 6.2 or newer: older SwiftPM copies .xcstrings
# catalogs into the resource bundle without compiling them to .lproj tables,
# so the localization tests have nothing to load.
#
# Usage: script/select_swiftpm_toolchain.sh [MIN_VERSION]   (default 6.2)
set -euo pipefail

min_version="${1:-6.2}"
best_dir=""
best_version=""

for xcode in /Applications/Xcode*.app; do
  swift_binary="$xcode/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
  [ -x "$swift_binary" ] || continue
  version=$("$swift_binary" -version 2>&1 | sed -nE 's/.*Swift version ([0-9]+(\.[0-9]+)+).*/\1/p' | head -1)
  echo "$xcode: Swift ${version:-unknown}"
  [ -n "$version" ] || continue
  if [ -z "$best_version" ] || [ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -1)" != "$best_version" ]; then
    best_version="$version"
    best_dir="$xcode/Contents/Developer"
  fi
done

if [ -z "$best_version" ] || [ "$(printf '%s\n%s\n' "$min_version" "$best_version" | sort -V | head -1)" != "$min_version" ]; then
  echo "::error title=Swift $min_version toolchain not found::No installed Xcode provides Swift $min_version or newer (newest found: ${best_version:-none})."
  exit 1
fi

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "DEVELOPER_DIR=$best_dir" >> "$GITHUB_ENV"
fi
echo "::notice title=Selected toolchain::$best_dir — Swift $best_version"
"$best_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" -version
