#!/usr/bin/env bash
#
# run_calibration.sh — drive ChronoframeVideoCalibrationTool against a local,
# labeled video corpus and archive the JSON report.
#
# This is a LOCAL-ONLY task: a real video corpus cannot live in the repo or CI
# (see docs/video-dedupe-calibration-rubric.md). Point this at a corpus that
# lives OUTSIDE the checkout, or under an ignored path like .tmp/.
#
# Usage:
#   script/video_calibration/run_calibration.sh --manifest <path> [tool flags...]
#   script/video_calibration/run_calibration.sh --corpus <dir>    [tool flags...]
#
# With --corpus, a manifest.json is generated from the directory layout first
# (see gen_manifest.py / README.md), then the tool is run against it.
#
# Any extra flags after the manifest/corpus are forwarded verbatim to the tool,
# e.g. --frame-hamming 7 --median 5 --aspect-tolerance 0.12 --low-variance 14.
#
# The JSON report is written next to the manifest as
#   <manifest-dir>/reports/calibration-YYYYmmdd-HHMMSS.json
# and the human-readable table is teed to a sibling .log.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sandbox-safe home + module caches, matching the rest of script/.
export HOME="$ROOT_DIR/.tmp/home"
export XDG_CACHE_HOME="$ROOT_DIR/.tmp/home/Library/Caches"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.tmp/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.tmp/modulecache"

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

MANIFEST=""
CORPUS=""
declare -a TOOL_FLAGS=()
declare -a GEN_FLAGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)          MANIFEST="${2:?--manifest needs a path}"; shift 2 ;;
    --corpus)            CORPUS="${2:?--corpus needs a path}"; shift 2 ;;
    --explode-underscore) GEN_FLAGS+=("$1"); shift ;;  # routed to gen_manifest.py
    -h|--help)           usage 0 ;;
    *)                   TOOL_FLAGS+=("$1"); shift ;;
  esac
done

if [[ -n "$CORPUS" && -n "$MANIFEST" ]]; then
  echo "error: pass either --corpus or --manifest, not both" >&2; exit 2
fi

if [[ -n "$CORPUS" ]]; then
  [[ -d "$CORPUS" ]] || { echo "error: corpus dir not found: $CORPUS" >&2; exit 2; }
  MANIFEST="$CORPUS/manifest.json"
  echo "==> Generating manifest from corpus layout: $CORPUS"
  python3 "$HERE/gen_manifest.py" "$CORPUS" --output "$MANIFEST" "${GEN_FLAGS[@]}"
elif [[ ${#GEN_FLAGS[@]} -gt 0 ]]; then
  echo "error: --explode-underscore only applies with --corpus" >&2; exit 2
fi

[[ -n "$MANIFEST" ]] || usage 2
[[ -f "$MANIFEST" ]] || { echo "error: manifest not found: $MANIFEST" >&2; exit 2; }

MANIFEST_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
REPORT_DIR="$MANIFEST_DIR/reports"
mkdir -p "$REPORT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
JSON_OUT="$REPORT_DIR/calibration-$STAMP.json"
LOG_OUT="$REPORT_DIR/calibration-$STAMP.log"

echo "==> Running calibration"
echo "    manifest: $MANIFEST"
echo "    report:   $JSON_OUT"
echo "    flags:    ${TOOL_FLAGS[*]:-(tool defaults)}"
echo ""

cd "$ROOT_DIR"
swift run --package-path ui ChronoframeVideoCalibrationTool \
  --manifest "$MANIFEST" \
  --output-json "$JSON_OUT" \
  "${TOOL_FLAGS[@]}" | tee "$LOG_OUT"

echo ""
echo "==> Saved report: $JSON_OUT"
echo "    Log:          $LOG_OUT"
echo "Record the chosen (T, H, A) + low-variance threshold and this report"
echo "path in the PR that changes any default — see the rubric §6 checklist."
