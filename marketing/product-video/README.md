# Chronoframe product film

A 44-second, 1920×1080 kinetic-typography product film in the style of the
short "launch" films indie Mac apps post to r/macapps, Product Hunt, and X:
large type sliding with motion blur over a soft amber gradient, hard cuts
between light and dark passages, and the real app shown in a MacBook frame
and in floating window cards.

## How it is built

The whole film is one HTML page, `index.html`. There are no CSS animations:
`window.render(t)` lays out every element as a pure function of time, so a
frame is reproducible on any machine. `render.py` drives headless Chrome
through Playwright, calls `render(t)` for `t = 0, 1/30, 2/30 …`, and
screenshots each frame. `build.sh` extracts the footage, renders the frames,
trims the music bed, and encodes with ffmpeg.

- Motion blur on the sliding headlines is a per-element SVG `feGaussianBlur`
  whose horizontal deviation follows the element's velocity that frame.
- The app footage is the raw captures under `../social-video/source-footage/`,
  extracted to 30 fps JPEG sequences in `seq/` so the page can scrub them.
- The music is the existing original Chronoframe cue
  (`../social-video/exports/Chronoframe-Youtube-Score.wav`), trimmed to length.
- The icon is `site/app-icon-1024.png`.

Open `index.html` directly in a browser to scrub it: Space pauses, arrow keys
step one frame, Shift+arrow steps one second.

## Rebuild

```bash
marketing/product-video/build.sh stills   # 16-frame contact sheet in work/
marketing/product-video/build.sh          # full render → exports/
```

Requires ffmpeg, `uv` (which fetches Playwright), and Google Chrome. A full
render takes a few minutes. The raw footage and the score it reads from
`../social-video/` are gitignored, so a rebuild only works on a Mac that has
those local captures. `seq/`, `work/`, and `icon.png` are generated and
ignored by git; `exports/` holds the committed deliverables.

## Timeline

| Time | Scene |
|------|-------|
| 0:00 | "twenty years of photos." / "are somewhere in here." over the messy source folder |
| 0:03 | Dark: phone backups, camera cards, that drawer of old drives (dock of folders with badge counts) |
| 0:07 | Loading ring → app icon → wordmark |
| 0:10 | "See the plan. Then say go." → MacBook with the preview, "Preview first." |
| 0:15 | Dark: it copies, it never moves / verifies every copy / originals untouched |
| 0:21 | "Keep the moment. Lose the extras." → side-by-side compare, keeper chosen |
| 0:27 | Dark: to the Trash, never a hard delete / changed your mind? / undo it |
| 0:33 | no account. no uploads. no subscription. |
| 0:36 | "Free to start." → "$14.99 once. no subscription." |
| 0:40 | Icon, chronoframe.app typed in, Mac App Store pill |

## Copy rules

Pricing lines must match `docs/APP_STORE_METADATA.md`: free to start, one
$14.99 US unlock, no subscription. "Never a hard delete" refers to the
Trash-only invariant; do not rewrite it as "never deleted".
