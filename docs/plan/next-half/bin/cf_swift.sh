#!/usr/bin/env bash
# Shared build/test wrapper for every docs/plan/* implementation plan.
# Same isolated HOME / module cache the CI lane and CLAUDE.md use.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export HOME="$ROOT/.tmp/home"
export XDG_CACHE_HOME="$ROOT/.tmp/home/Library/Caches"
export CLANG_MODULE_CACHE_PATH="$ROOT/.tmp/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.tmp/modulecache"
mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"
cd "$ROOT"
case "${1:-}" in
  build)  swift build --package-path ui --build-tests --disable-sandbox ;;
  test)   swift test --package-path ui --disable-sandbox --filter "${2:?usage: cf_swift.sh test FILTER}" ;;
  suite)  script/run_swift_test_suites.sh ;;
  coverage) script/swift_meaningful_coverage.sh ;;
  guards)
    status=0
    for g in check_agents_invariants_have_tests check_app_intents_never_purchase \
             check_authorizer_has_no_default check_detail_views_set_navigation_title \
             check_guardian_restore_verified check_mas_build_lane_exists \
             check_no_await_in_xctassert check_no_raw_animations check_photos_import_readonly \
             check_recovery_goes_through_helper check_storekit_config_matches_policy \
             check_test_dirs_are_targets check_uitest_membership; do
      if "script/$g.sh"; then echo "GUARD $g: 0"; else echo "GUARD $g: $?"; status=1; fi
    done
    # App-layer guard takes the base ref as an argument; default main.
    if script/check_app_layer_changes_have_tests.sh "${2:-main}"; then echo "GUARD check_app_layer_changes_have_tests: 0"; else echo "GUARD check_app_layer_changes_have_tests: $?"; status=1; fi
    exit $status ;;
  xcode)
    xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug \
      -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" \
      CODE_SIGNING_ALLOWED=NO build ;;
  *) echo "usage: cf_swift.sh build | test FILTER | suite | coverage | guards [BASE_REF] | xcode" >&2; exit 2 ;;
esac
