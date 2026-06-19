# Perceptual Video Dedupe — Calibration & Labeling Rubric (Milestone 2c)

This document is the **ground-truth labeling rubric** for tuning the perceptual
video matcher. Choosing thresholds — `durationToleranceSeconds (T)`,
`frameHammingThreshold (H)`, `aggregateMedianThreshold (A)`, and the extractor's
`lowVarianceThreshold` — must be driven by a **labeled corpus**, never intuition.
Without a written rubric, "precision" and "recall" are one labeler's opinion.

The labels here feed `ChronoframeVideoCalibrationTool` (see below), which is a
local-only harness: a real video corpus cannot live in the repo or CI.

---

## 1. Asymmetric error policy (read this first)

The operating point is chosen under a deliberately **asymmetric** cost model:

- We **accept** missing some true transcodes (recall < 100%).
- We **do not accept** a false auto-selection of a delete.

Perceptual video clusters are always **review-only**: medium-capped by
`ClusterConfidenceScorer` and rejected by
`DeduplicationPlanner.isAutomaticCommitEligible` (AGENTS-INVARIANT 6). Calibration
therefore only tunes **which clusters are surfaced for review**, never whether
anything is deleted automatically. When a threshold choice trades precision for
recall, prefer precision.

---

## 2. The match question

Two videos are a **match** (should be surfaced in the same review cluster) when a
person would call them *the same recording* — one is a re-encode, re-wrap,
resize, or container change of the other, possibly with cosmetic letterboxing or
metadata differences. They are a **non-match** when they are merely *related*
(same event, shared intro, same camera) but are genuinely different recordings.

The matcher is duration-prefiltered and aspect-gated, then decides on frame-hash
agreement at aligned sample fractions. The rubric below resolves the ambiguous
classes a labeler will actually hit.

---

## 3. Per-class labeling decisions

For each ambiguous class, the table fixes **match / non-match** so labeling is
reproducible across people.

| Class | Description | Label | Rationale |
|---|---|---|---|
| **Transcode** | Same recording, different codec/bitrate (H.264 ↔ HEVC) | **Match** | Canonical duplicate; the feature we ship for. |
| **Container re-wrap** | Same stream, `.mov` ↔ `.mp4` | **Match** | Identical frames. |
| **Resize** | Same recording at 4K vs 1080p | **Match** | dHash is resolution-tolerant; aspect unchanged. |
| **Letterbox / pillarbox re-export** | Same recording with added black bars | **Match**, *only if* added bars keep aspect within `aspectRatioTolerance`; otherwise **non-match** | Bars change framing; small bars are still the same shot, large ones change aspect and are correctly rejected. |
| **Anamorphic / non-square PAR** | Same recording, different pixel aspect ratio flag | **Match** if display aspect (post-transform) agrees within tolerance | We compare *display* dimensions, not coded. |
| **Rotation** | Same recording, rotation-flag vs baked-in rotation | **Match** | `appliesPreferredTrackTransform` normalizes both. |
| **Short trim (≤ ~2s off either end)** | Same recording, slightly trimmed | **Match** *if* still within `T` and ≥3 aligned informative frames overlap; else **non-match** | Interior-biased sampling tolerates small trims; large trims drift toward partial-clip matching (out of scope). |
| **Same event, different clip** | Two separate recordings of one event | **Non-match** | Different recordings — must not cluster. Primary hard negative. |
| **Shared intro / bumper** | Different videos sharing an identical intro | **Non-match** | Interior sampling + median rule should reject; a key hard negative. |
| **Static slideshow / talking head** | Low-motion clips that look alike | **Non-match** unless actually the same recording | Tests false positives from low inter-frame variation. |
| **Black frames / fades** | Clip dominated by uniform frames | **Non-match** as a *pair signal*; individually expect `insufficientVisualEvidence` | Low-variance discard should null these slots. |
| **Short / low-motion clip** | Too few informative frames | Expect `insufficientVisualEvidence` (not a match either way) | Decode succeeds but evidence is insufficient; cached and skipped. |

**Decode-status labels** (orthogonal to match/non-match): `ready`,
`unsupported` (container AVFoundation can't open), `decodeFailed` (no frame
decoded), `insufficientVisualEvidence` (decoded, too few informative frames).
Label these from the actual file when known, so extractor-side regressions
(e.g. a too-aggressive `lowVarianceThreshold`) are caught.

---

## 4. Manifest format

`ChronoframeVideoCalibrationTool` consumes a JSON manifest the labeler maintains
locally. Items sharing a `truthGroup` of size > 1 are ground-truth duplicates;
singleton groups are non-duplicates. `class` is free-form (use the names above)
and is reported in per-class breakdowns.

```json
{
  "items": [
    { "path": "/corpus/beach_h264.mp4",  "truthGroup": "beach",   "class": "transcode" },
    { "path": "/corpus/beach_hevc.mov",  "truthGroup": "beach",   "class": "container" },
    { "path": "/corpus/beach_1080p.mp4", "truthGroup": "beach",   "class": "resize" },
    { "path": "/corpus/party_clipA.mov", "truthGroup": "party-a", "class": "same-event" },
    { "path": "/corpus/party_clipB.mov", "truthGroup": "party-b", "class": "same-event" },
    { "path": "/corpus/black_intro.mp4", "truthGroup": "solo-1",  "class": "black-frames" }
  ]
}
```

Paths must be absolute and readable on the calibrating machine.

---

## 5. Metrics the harness reports

Run:

```bash
swift run --package-path ui ChronoframeVideoCalibrationTool \
  --manifest /corpus/manifest.json \
  --output-json /corpus/results/chronoframe-video-calibration.json
```

Reported metrics (all defined against the rubric labels above):

- **Candidate-index recall** — fraction of true duplicate pairs that survive the
  pre-match prune (duration window + aspect gate). This is the recall ceiling:
  a pair pruned here can never be recovered by threshold tuning.
- **Pair precision / recall** — over all unordered pairs, predicted-same-cluster
  vs. ground-truth-same-group.
- **Cluster purity** — fraction of clustered items whose predicted cluster is
  dominated by a single `truthGroup`.
- **Hard-negative false-positive rate** — distinct-group pairs predicted as
  matches (the error class we most want near zero).
- **Per-class recall** — recall broken out by `class`, so a regression in
  (say) letterbox handling is visible.
- **Throughput** — videos analyzed per second (cold extraction).
- **Resident memory** — process resident size after extraction (sanity-check
  that the `maximumDecodeDimension` cap holds).
- **Warm-vs-cold stability** — re-running must yield identical normalized member
  sets and keeper paths (cluster UUIDs are random and excluded).
- **Threshold sensitivity** — precision/recall swept around the operating
  `(T, H, A)`, so the chosen point is not sitting on a precision cliff.

---

## 6. Choosing the operating point

1. Confirm **candidate-index recall** is high (≈1.0). If true pairs are pruned,
   widen `T` or `aspectRatioTolerance` before touching the frame thresholds.
2. On the **sensitivity curves**, pick the `(H, A)` with the lowest
   hard-negative false-positive rate that still clears your recall floor. Prefer
   a point on a flat region, not a cliff edge.
3. Set `lowVarianceThreshold` from the decode-status labels: it should null
   black/fade frames (so they don't create spurious agreements) without nulling
   genuine low-contrast-but-informative frames.
4. Re-run; verify warm-vs-cold stability is exact.

Record the chosen values and the corpus/commit they were derived from in the PR
that changes any default in `VideoPerceptualMatchConfiguration` or
`VideoFeatureExtractionConfiguration`.

The JSON report is the durable calibration artifact. Keep it beside the private
corpus rather than committing media or absolute corpus paths to this repository.
Before changing defaults, include these fields in the PR description:

- Chronoframe commit and macOS/hardware used for extraction.
- Corpus revision, item count, and class distribution.
- JSON report path or attached redacted report.
- Chosen `(T, H, A)` and low-variance threshold.
- Pair precision/recall, hard-negative false-positive rate, candidate-index
  recall, cluster purity, and warm/cold stability.
- A short explanation for any threshold that differs from the report's flattest
  high-precision operating region.
