# Chronoframe — YouTube and social films

Start with **`exports/Chronoframe-YouTube-4K.mp4`** and
**`exports/Chronoframe-Social-Vertical-1080x1920.mp4`**.

The 60-second film follows scattered folders → dated library → preview → verified copies
→ duplicate comparison → approval → restoration → local privacy. The separate 30-second
vertical edit opens with the photo comparison and uses larger captions and focused crops.
Both have an original instrumental score, visible benefit captions, and a chronoframe.app CTA.
They communicate the full story with sound muted. There is no voiceover.

## Delivery files

| File in `exports/` | Use |
|---|---|
| `Chronoframe-YouTube-4K.mp4` | 60-second 3840×2160 master; upload this to YouTube |
| `Chronoframe-YouTube-1080p.mp4` | Smaller 1920×1080 review/sharing copy |
| `Chronoframe-Social-Vertical-1080x1920.mp4` | 30-second 9:16 social / Shorts edit |
| `Chronoframe-YouTube-Thumbnail.jpg` | 1280×720 thumbnail extracted from the closing shot |
| `Chronoframe-Youtube-Poster.png` | Full-resolution horizontal comparison poster |
| `Chronoframe-Vertical-Poster.png` | Vertical cover extracted from the opening |
| `Chronoframe-Youtube.srt` / `.vtt` | Timed horizontal caption transcript |
| `Chronoframe-Vertical.srt` / `.vtt` | Timed vertical caption transcript |
| `Chronoframe-Youtube-Score.wav` | 60-second original music, 24-bit stereo / 48 kHz |
| `Chronoframe-Vertical-Score.wav` | 30-second original music, 24-bit stereo / 48 kHz |
| `quality-report.json` | Checksums, frame/decode checks, measured format and audio levels |

All videos are progressive 30 fps H.264 High, yuv420p, BT.709, with fast-start MP4 and
stereo AAC at 48 kHz. The encoder targets 384 kbps AAC; the simple instrumental score
averages approximately 300 kbps. Music measures −16.9 LUFS integrated, with true peaks
below −5 dBTP. Video quality uses CRF encoding, so static UI scenes need fewer bits than
camera footage. The two masters omit MP4 edit lists; codec priming adds about 67 ms to
container duration while the video edits are exactly 1,800 and 900 frames.

The videos have **not been uploaded**. Draft titles and descriptions are in
`publishing-copy.md`. Captions are already visible in the video; the sidecars are available
for accessibility and reuse. The 4K master is the recommended horizontal upload.

## Source, rights, and product truth

This production reuses the September 21 real development-app recordings used for the
approved App Store preview. The depicted views were checked against the September 27
development checkout during that production; the development app built successfully.
This is an edited reuse of those recordings, not a claim of fresh capture today.
No simulated app screens, fabricated clicks, or real customer photo library are used.
The 4,000-photo example is a staged demonstration, not a performance benchmark.

The sole visible photograph is **Sandboarding in Dubai**, Steven J. Weber, U.S. Navy,
listed as public domain on its
[source page](https://commons.wikimedia.org/wiki/File:Sandboarding_in_Dubai.jpg).
Edited variants appear in the staged duplicate comparison. Other photo thumbnails in the
raw recordings are covered by the caption rail or excluded by the vertical crop.
The film includes the photo credit and does not imply endorsement.

The score is composed and synthesized in `score.py` from oscillators and generated
percussion. It uses no external samples, stock loops, or commercial recordings. It develops
the same musical palette as the approved App Store film into 60- and 30-second arrangements.

The organize claim applies to source files. Duplicate removal is separately approved and
moves selected files to macOS Trash. Restoration requires the recorded file still to exist
in Trash with its recorded contents; it cannot recover an emptied Trash. The confirmation
shown in the film explains the Trash limitation. No price or trial terms are asserted.

## Reproduction and checks

`produce.py` owns the shot list, timing, text, crops, graphics, transitions and encoding.
`edit.json` is its generated edit manifest. `source-provenance.json` records raw-file hashes.
`source-footage/`, `work/` and `exports/` are ignored by Git: retain those directories with
the scripts when archiving the production.

Requires FFmpeg, Python with NumPy/Pillow, and the macOS SF system font. On this Mac:

```sh
/Users/nishithnand/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 marketing/social-video/produce.py all --profile youtube
/Users/nishithnand/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 marketing/social-video/produce.py all --profile vertical
/Users/nishithnand/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 marketing/social-video/verify.py
```

Individual stages are `prepare`, `music`, `render`, and `finish`. Run `prepare` after changing
caption copy. Individual scene renders are cached by graphics, crop and edit settings.

Visual checks cover full-edit contact sheets, full-size comparisons, confirmations, restoration,
and final CTA. Verification decodes every frame of all three delivered MP4s and checks
resolution, frame rate, color, audio, duration, fast-start ordering, and full-frame black gaps.
Audio has been measured technically; it has not been auditioned through a listening tool.
No production app source was changed for this video work.

Platform references checked September 27, 2026:

- [YouTube encoding recommendations](https://support.google.com/youtube/answer/1722171?hl=en)
- [YouTube Shorts format guidance](https://support.google.com/youtube/answer/15424877?hl=en-GB)
