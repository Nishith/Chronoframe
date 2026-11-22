#!/bin/zsh
# Rebuild the Chronoframe product film from source footage.
#
#   marketing/product-video/build.sh            # full build
#   marketing/product-video/build.sh stills     # review contact sheet only
#
# Needs: ffmpeg, uv (fetches Playwright), Google Chrome (used headless).
# Intermediate frames live under work/ and are not committed.
set -euo pipefail
HERE="${0:A:h}"
FOOTAGE="$HERE/../social-video/source-footage"
SCORE="$HERE/../social-video/exports/Chronoframe-Youtube-Score.wav"
WORK="$HERE/work"
OUT="$HERE/exports"
mkdir -p "$WORK" "$OUT"

# 1. Footage -> 30 fps JPEG sequences the page can scrub deterministically.
extract() {
  local name=$1 src=$2 dur=$3 width=$4
  [[ -d "$HERE/seq/$name" ]] && return
  mkdir -p "$HERE/seq/$name"
  ffmpeg -v error -y -t "$dur" -i "$FOOTAGE/$src" -vf "fps=30,scale=$width:-2" -q:v 3 "$HERE/seq/$name/%04d.jpg"
}
extract src         hero-source-finder-raw.mov         4   1400
extract org         hero-organized-finder-raw.mov      4   1400
extract preview     01-mas-opening-preview-raw.mov     6   1600
extract transfer    02-mas-transfer-complete-raw.mov   6   1600
extract compare     03-mas-sandboarding-choice-raw.mov 7.9 1600
extract keeper      03b-mas-sandboarding-keeper-raw.mov 3.9 1600
extract trashreview 04a-mas-trash-review-raw.mov       3.9 1600
extract trash       04b-mas-trash-confirmation-raw.mov 2.9 1600
extract history     05a-mas-history-before-revert-raw.mov 3.9 1600
extract revert      05b-mas-revert-confirmation-raw.mov 2.9 1600
extract restored    05c-mas-revert-complete-raw.mov    3.9 1600
cp -f "$HERE/../../site/app-icon-1024.png" "$HERE/icon.png"

if [[ "${1:-}" == "stills" ]]; then
  rm -rf "$WORK/stills"
  uv run --with playwright python -I "$HERE/render.py" stills \
    0.9,2.4,5.6,8.4,10.6,13.4,16.2,18.4,22.2,24.4,28.3,30.4,33.9,36.9,38.9,43.5 "$WORK/stills"
  ffmpeg -v error -y -pattern_type glob -i "$WORK/stills/*.png" -vf "scale=640:-1,tile=4x4" "$WORK/stills-sheet.png"
  echo "contact sheet: $WORK/stills-sheet.png"
  exit 0
fi

# 2. Every frame is window.render(t); render them all.
rm -rf "$WORK/frames"
uv run --with playwright python -I "$HERE/render.py" full "$WORK/frames"

# 3. Music bed: the existing original Chronoframe cue, trimmed to length.
ffmpeg -v error -y -i "$SCORE" \
  -af "atrim=0:44.5,afade=t=in:st=0:d=0.6,afade=t=out:st=41.8:d=2.7,loudnorm=I=-18:TP=-1.5:LRA=9" \
  -ar 48000 -ac 2 "$WORK/score-44s.wav"

# 4. Encode. H.264 High 4:2:0 for broad playback; a silent variant for autoplay embeds.
ffmpeg -v error -y -framerate 30 -i "$WORK/frames/%05d.png" -i "$WORK/score-44s.wav" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -profile:v high -level 4.1 \
  -c:a aac -b:a 192k -movflags +faststart -shortest \
  "$OUT/Chronoframe-Product-Film-1080p.mp4"
ffmpeg -v error -y -i "$OUT/Chronoframe-Product-Film-1080p.mp4" -an -c:v copy \
  "$OUT/Chronoframe-Product-Film-1080p-silent.mp4"
cp -f "$WORK/frames/01260.png" "$OUT/Chronoframe-Product-Film-Poster.png"
echo "done: $OUT"
