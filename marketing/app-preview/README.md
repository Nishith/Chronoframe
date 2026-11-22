# Chronoframe App Store preview

**Start with `exports/Chronoframe-App-Store-Preview.mp4`.**

A 29.8-second film using real development-app recordings, benefit-led captions and an
original instrumental score. It demonstrates preview, organizing, duplicate comparison,
Trash approval and restoration from History. The story works with sound muted.

## Deliverables

| File in `exports/` | Purpose |
|---|---|
| `Chronoframe-App-Store-Preview.mp4` | Finished preview with stereo music and visible captions |
| `Chronoframe-App-Store-Silent.mp4` | Same captioned edit without audio |
| `Chronoframe-Poster.png` | Poster extracted at 11.5 seconds |
| `Chronoframe-Captions.srt` / `.vtt` | Caption transcript for later reuse |
| `Chronoframe-Original-Score.wav` | Original stereo music master, 24-bit / 48 kHz |
| `quality-report.json` | Machine-checked media specifications and measured audio |

For App Store Connect, use the main MP4 and set the poster timestamp to **11.5 seconds**
to match the provided image. The preview has not been uploaded or submitted for review.
Submit alongside a build with the features shown. Apple remains the final review authority.

The Mac App Store accepts 1920×1080 and 15–30 seconds. The longer 4K website/social film
is a separate follow-up. References checked September 27, 2026:

- [Apple preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)
- [Apple preview creative guidance](https://developer.apple.com/app-store/app-previews/)

## Edit and provenance

`produce.py` is the editable production source. `edit.json` records the generated shot list;
edit `SCENES` in the script to change timing or copy. `source-footage/` preserves the source
recordings and `source-provenance.json` records SHA-256 identities. `work/` holds intermediates
and the review contact sheet. Generated media is git-ignored; retain it separately when moving
this production to another machine.

The footage was recorded September 21, 2026. It is reused, not represented as a new capture.
The depicted views are unchanged in the current development checkout. The September 27
development build compiled successfully and its running interface was inspected.
Fixed editorial crops enlarge relevant UI; short dissolves join shots. No simulated UI,
fabricated mouse clicks, time-to-complete claim, or new mutation of a real photo library was used.

The sole visible photograph is **Sandboarding in Dubai**, Steven J. Weber, U.S. Navy,
identified on its [source page](https://commons.wikimedia.org/wiki/File:Sandboarding_in_Dubai.jpg)
as public domain. On-screen credit is included. The demo uses edited variants of that image;
its displayed capture date is part of the staged library. Other photo thumbnails in the raw
recordings are fully covered by the caption rail and do not appear in the final video.
No endorsement by the photographer, subject or Navy is implied.

Music was composed and synthesized for this film with no external samples, stock loops or
commercial recording. The score's construction is in `produce.py`; see `music-provenance.txt`.

## Rebuild on this Mac

Requires FFmpeg, NumPy, Pillow and the macOS SF system font. The local bundled Python is:

```sh
/Users/nishithnand/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 marketing/app-preview/produce.py all
```

Individual stages: `prepare`, `score`, `render`, `mux`. Rendering caches individual shots by
caption content and edit settings. Always run `prepare` after changing captions. `verify.py`
checks the final technical deliverable and regenerates its quality report.

## Validation performed

- Successful build of the current development app; no production-source changes for this task.
- Visual inspection of opening, comparison, confirmation and restore shots, and a contact sheet
  sampled through the full edit. Captions stay readable; there are no unrelated windows or
  personal home-directory paths in the rendered footage.
- Full decode of all 894 frames; no decoding errors or full-frame black gaps detected.
- 1920×1080, constant 30 fps, H.264 High Level 4.0, progressive yuv420p, BT.709.
- 29.8 seconds, approximately 41.7 MB, video approximately 10.93 Mbps.
- AAC-LC stereo, 48 kHz, approximately 256 kbps. Measured −17.9 LUFS integrated,
  −6.9 dBTP; no clipping. Audio was analyzed technically, not auditioned through a listening tool.

The final creative judgment on the musical timbre and pacing should be made by playing the
delivered video. Technical format validation is not an App Store approval guarantee.
