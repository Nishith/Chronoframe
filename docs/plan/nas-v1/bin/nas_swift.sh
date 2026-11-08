#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export HOME="$ROOT/.tmp/home"
export XDG_CACHE_HOME="$ROOT/.tmp/home/Library/Caches"
export CLANG_MODULE_CACHE_PATH="$ROOT/.tmp/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.tmp/modulecache"
mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"
cd "$ROOT"
case "${1:-}" in
  build) swift build --package-path ui --build-tests --disable-sandbox ;;
  test) swift test --package-path ui --disable-sandbox --filter "${2:?usage: nas_swift.sh test FILTER}" ;;
  *) echo "usage: nas_swift.sh build | test FILTER" >&2; exit 2 ;;
esac
