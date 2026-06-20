#!/usr/bin/env bash
#
# make_variants.sh — turn one source video into a full "duplicate set" for the
# perceptual-video calibration corpus. Every output is the SAME recording stored
# differently (transcode / re-wrap / resize / letterbox), which is exactly what
# the matcher should cluster. See script/video_calibration/README.md.
#
# Usage:
#   script/video_calibration/make_variants.sh <source-video> [options]
#
# Options:
#   --name <group>     Folder/group name (default: source filename without ext)
#   --corpus <dir>     Corpus root (default: $CHRONOFRAME_CORPUS or
#                      ~/chronoframe-video-corpus)
#   --no-original      Don't copy the source into the group folder
#
# Outputs land in <corpus>/<group>/ as:
#   <group>_original.<ext>        (a copy of the source, unless --no-original)
#   transcode__<group>_hevc.mov
#   transcode__<group>_h264.mp4
#   container__<group>_rewrap.mp4
#   resize__<group>_1080p.mp4
#   resize__<group>_720p.mp4
#   letterbox__<group>_bars.mp4

set -euo pipefail

usage() { sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

command -v ffmpeg >/dev/null 2>&1 || {
  echo "error: ffmpeg not found. Install it with:  brew install ffmpeg" >&2
  exit 1
}

SOURCE=""
GROUP=""
CORPUS="${CHRONOFRAME_CORPUS:-$HOME/chronoframe-video-corpus}"
COPY_ORIGINAL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        GROUP="${2:?--name needs a value}"; shift 2 ;;
    --corpus)      CORPUS="${2:?--corpus needs a path}"; shift 2 ;;
    --no-original) COPY_ORIGINAL=0; shift ;;
    -h|--help)     usage 0 ;;
    -*)            echo "error: unknown option $1" >&2; usage 2 ;;
    *)             SOURCE="$1"; shift ;;
  esac
done

[[ -n "$SOURCE" ]] || usage 2
[[ -f "$SOURCE" ]] || { echo "error: source video not found: $SOURCE" >&2; exit 2; }

# Default group name = source filename without its extension.
if [[ -z "$GROUP" ]]; then
  base="$(basename "$SOURCE")"
  GROUP="${base%.*}"
fi
ext="${SOURCE##*.}"

OUT_DIR="$CORPUS/$GROUP"
mkdir -p "$OUT_DIR"

echo "==> Source: $SOURCE"
echo "    Group:  $GROUP"
echo "    Output: $OUT_DIR"
echo ""

# ffmpeg flags: -y overwrite, quiet logs, -nostdin so a loop never eats stdin.
FF=(ffmpeg -hide_banner -loglevel error -nostdin -y)

if [[ "$COPY_ORIGINAL" -eq 1 ]]; then
  echo "  - original copy"
  cp "$SOURCE" "$OUT_DIR/${GROUP}_original.$ext"
fi

echo "  - transcode -> HEVC"
"${FF[@]}" -i "$SOURCE" -c:v libx265 -crf 28 -tag:v hvc1 -c:a copy \
  "$OUT_DIR/transcode__${GROUP}_hevc.mov"

echo "  - transcode -> H.264"
"${FF[@]}" -i "$SOURCE" -c:v libx264 -crf 23 -c:a copy \
  "$OUT_DIR/transcode__${GROUP}_h264.mp4"

echo "  - container re-wrap (.mp4, no re-encode)"
"${FF[@]}" -i "$SOURCE" -c copy \
  "$OUT_DIR/container__${GROUP}_rewrap.mp4"

echo "  - resize -> 1080p"
"${FF[@]}" -i "$SOURCE" -vf "scale=-2:1080" -c:v libx264 -crf 23 -c:a copy \
  "$OUT_DIR/resize__${GROUP}_1080p.mp4"

echo "  - resize -> 720p"
"${FF[@]}" -i "$SOURCE" -vf "scale=-2:720" -c:v libx264 -crf 23 -c:a copy \
  "$OUT_DIR/resize__${GROUP}_720p.mp4"

echo "  - letterbox (padded bars)"
"${FF[@]}" -i "$SOURCE" -vf "scale=-2:960,pad=ih*16/9:ih:(ow-iw)/2:0" \
  -c:v libx264 -crf 23 -c:a copy \
  "$OUT_DIR/letterbox__${GROUP}_bars.mp4"

echo ""
echo "==> Done. $(ls -1 "$OUT_DIR" | wc -l | tr -d ' ') files in $OUT_DIR"
echo "Run another source to add more groups, then calibrate with:"
echo "  script/video_calibration/run_calibration.sh --corpus \"$CORPUS\" --explode-underscore"
