#!/bin/sh
# Stamps the built Info.plist with a 3-part Major.Minor.Build version.
# Major.Minor come from MARKETING_VERSION; Build is the Git commit count, which
# is monotonic so that newer builds win Launch Services icon resolution.
#
# Build number resolution order:
#   1. CHRONOFRAME_BUILD_NUMBER  (lets CI inject a monotonic number directly)
#   2. git rev-list --count HEAD (deepening a shallow clone first if possible)
#   3. CURRENT_PROJECT_VERSION   (last-resort fallback)
#
# Shallow clones (e.g. actions/checkout without fetch-depth: 0) report a commit
# count of 1, which would make build numbers non-monotonic. We detect that case,
# try to deepen, and warn loudly rather than silently stamping a bogus number.
set -u

REPO="${SRCROOT:-$(pwd)}"
BUILD="${CHRONOFRAME_BUILD_NUMBER:-}"

is_shallow() {
  [ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]
}

if [ -z "$BUILD" ]; then
  if is_shallow; then
    git -C "$REPO" fetch --unshallow --quiet 2>/dev/null || true
  fi
  if is_shallow; then
    echo "warning: shallow Git clone; commit count is unreliable. Set CHRONOFRAME_BUILD_NUMBER or check out with fetch-depth: 0." >&2
    BUILD="${CURRENT_PROJECT_VERSION:-0}"
  else
    BUILD="$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || true)"
  fi
fi
[ -z "$BUILD" ] && BUILD="${CURRENT_PROJECT_VERSION:-0}"

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$PLIST" ]; then
  echo "warning: Info.plist not found at $PLIST; skipping version stamp" >&2
  exit 0
fi

SHORT="${MARKETING_VERSION}.${BUILD}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" "$PLIST"
echo "Stamped version ${SHORT} (build ${BUILD})"
