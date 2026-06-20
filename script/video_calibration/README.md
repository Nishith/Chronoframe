# Perceptual video dedupe — calibration runner

Local-only scaffolding for choosing the perceptual-video thresholds against a
**labeled corpus**, as required before changing any default in
`VideoPerceptualMatchConfiguration` or `VideoFeatureExtractionConfiguration`.

- **Why this is local-only:** a real video corpus cannot live in the repo or
  CI. Keep the corpus and reports OUTSIDE the checkout, or under the ignored
  `.tmp/` path. Only the redacted JSON report belongs in a PR.
- **The rules that matter:** read [`docs/video-dedupe-calibration-rubric.md`](../../docs/video-dedupe-calibration-rubric.md)
  first — it defines the asymmetric error policy (precision > recall), the
  per-class match/non-match labels, and the §6 operating-point checklist.

## 1. Lay out the corpus

Each immediate subdirectory of the corpus root is one ground-truth group.
Filenames may encode the rubric `class` as a `class__` prefix:

```
~/chronoframe-video-corpus/
  beach/                       # truthGroup "beach" — all the SAME recording
    beach_original.mov
    transcode__beach_hevc.mov
    container__beach_rewrap.mp4
    resize__beach_1080p.mp4
    letterbox__beach_bars.mp4
  party-a/                     # singleton group -> a non-duplicate
    same-event__clipA.mov
  party-b/
    same-event__clipB.mov
  _solo/                       # hard negatives; one singleton per file
    shared-intro__bumper_x.mp4
    black-frames__fade.mp4
    static-slideshow__deck.mov
```

- **Duplicate groups** = folder with > 1 file (the same recording, transcoded /
  re-wrapped / resized / letterboxed).
- **Hard negatives** = unrelated clips that *look* related (same event, shared
  intro, low-motion). These drive the hard-negative false-positive rate, the
  number we most want near zero. Put each in its own folder, or drop them all in
  a `_`-prefixed folder and use `--explode-underscore`.

`manifest.example.json` shows the literal JSON shape if you'd rather hand-write
it instead of using the folder convention.

## 2. Run it

```bash
# From the corpus folder layout (generates manifest.json, then runs the tool):
script/video_calibration/run_calibration.sh \
  --corpus ~/chronoframe-video-corpus --explode-underscore

# Or from an existing manifest:
script/video_calibration/run_calibration.sh \
  --manifest ~/chronoframe-video-corpus/manifest.json
```

Anything after the corpus/manifest is forwarded to the tool, so you can probe a
candidate operating point directly:

```bash
script/video_calibration/run_calibration.sh \
  --manifest ~/chronoframe-video-corpus/manifest.json \
  --frame-hamming 7 --median 5 --aspect-tolerance 0.12 --low-variance 14
```

Each run writes a timestamped `reports/calibration-*.json` (the durable
artifact) and a `.log` of the human-readable table, including the threshold
sensitivity sweep around your chosen `(H, A)`.

## 3. Choose the operating point

Follow the rubric §6 loop:

1. Confirm **candidate-index recall ≈ 1.0**. If true pairs are pruned, widen
   `--duration-tolerance` or `--aspect-tolerance` before touching frame
   thresholds.
2. On the sweep grid, pick the `(H, A)` with the lowest **hard-negative FP
   rate** that still clears your recall floor — prefer a flat region, not a
   cliff.
3. Set `--low-variance` so black/fade frames are nulled without nulling genuine
   low-contrast frames (watch the decode-status breakdown).
4. Re-run; confirm **warm-vs-cold stable: yes**.

Then update the defaults in
[`VideoPerceptualMatcher.swift`](../../ui/Sources/ChronoframeCore/VideoPerceptualMatcher.swift)
/ [`VideoFeatureExtractor.swift`](../../ui/Sources/ChronoframeCore/VideoFeatureExtractor.swift)
and put the rubric §6 fields (commit, hardware, corpus revision/size/class mix,
chosen `(T, H, A)` + low-variance, and the headline metrics) in the PR
description. Attach the redacted JSON report — never the media or absolute paths.

Perceptual video stays **review-only** regardless of calibration: medium-capped
and never auto-selected for deletion. Calibration only tunes which clusters are
surfaced for review.
