#!/usr/bin/env python3
"""Generate a ChronoframeVideoCalibrationTool manifest from a corpus directory.

The manifest format and labeling rules live in
docs/video-dedupe-calibration-rubric.md. This generator removes the tedium of
hand-writing absolute paths: it derives `truthGroup` and `class` from a simple
on-disk convention, so building the corpus is "drop files in the right folder".

Layout convention
------------------
Each immediate subdirectory of the corpus root is one ground-truth group:

    corpus/
      beach/                      # truthGroup "beach" — all the same recording
        transcode__beach_hevc.mov
        resize__beach_1080p.mp4
        beach_original.mov        # no "class__" prefix -> class omitted
      party-a/                    # singleton group -> non-duplicate
        same-event__clipA.mov
      party-b/
        same-event__clipB.mov
      _solo/                      # a folder of unrelated singletons (see below)
        black-frames__intro.mp4
        slideshow__deck.mov

- truthGroup = subdirectory name. Items sharing a group of size > 1 are
  ground-truth duplicates; a group of size 1 is a non-duplicate.
- class = the token before a "__" in the filename (e.g. "transcode",
  "resize", "same-event", "black-frames"). Omitted if there is no "__".
  Use the class names from the rubric so per-class recall lines up.

Singletons: a real corpus needs many unrelated non-duplicates as hard
negatives. Put each in its own group folder, OR drop them all in a folder whose
name starts with "_" (e.g. "_solo") and pass --explode-underscore so every file
there becomes its own singleton group (named "<folder>-<filename>").

Usage:
    gen_manifest.py <corpus-dir> [--output manifest.json] [--explode-underscore]
"""
from __future__ import annotations

import argparse
import json
import os
import sys

VIDEO_EXTS = {".mov", ".mp4", ".m4v", ".avi", ".mkv", ".mpg", ".mpeg", ".hevc", ".webm"}


def derive_class(filename: str) -> str | None:
    stem = os.path.splitext(filename)[0]
    if "__" in stem:
        token = stem.split("__", 1)[0].strip()
        return token or None
    return None


def is_video(filename: str) -> bool:
    return os.path.splitext(filename)[1].lower() in VIDEO_EXTS


def build_items(corpus_dir: str, explode_underscore: bool) -> list[dict]:
    items: list[dict] = []
    for group in sorted(os.listdir(corpus_dir)):
        group_dir = os.path.join(corpus_dir, group)
        if not os.path.isdir(group_dir) or group.startswith("."):
            continue
        explode = explode_underscore and group.startswith("_")
        for name in sorted(os.listdir(group_dir)):
            if not is_video(name):
                continue
            abs_path = os.path.abspath(os.path.join(group_dir, name))
            # Include the full filename (with extension) so two hard negatives
            # sharing a stem (clip.mov / clip.mp4) stay distinct singleton
            # groups instead of being mislabeled as duplicates.
            truth_group = f"{group}-{name}" if explode else group
            item: dict = {"path": abs_path, "truthGroup": truth_group}
            cls = derive_class(name)
            if cls:
                item["class"] = cls
            items.append(item)
    return items


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("corpus_dir", help="Root directory of the labeled corpus")
    parser.add_argument("--output", "-o", help="Manifest path (default: <corpus-dir>/manifest.json)")
    parser.add_argument(
        "--explode-underscore",
        action="store_true",
        help='Treat each file in "_"-prefixed folders as its own singleton group',
    )
    args = parser.parse_args()

    corpus_dir = os.path.abspath(args.corpus_dir)
    if not os.path.isdir(corpus_dir):
        print(f"error: not a directory: {corpus_dir}", file=sys.stderr)
        return 2

    items = build_items(corpus_dir, args.explode_underscore)
    if not items:
        print(f"error: no video files found under {corpus_dir}", file=sys.stderr)
        return 2

    output = args.output or os.path.join(corpus_dir, "manifest.json")
    with open(output, "w", encoding="utf-8") as fh:
        json.dump({"items": items}, fh, indent=2)
        fh.write("\n")

    groups = {it["truthGroup"] for it in items}
    dup_groups = {g for g in groups if sum(1 for it in items if it["truthGroup"] == g) > 1}
    print(f"wrote {output}")
    print(f"  items:            {len(items)}")
    print(f"  groups:           {len(groups)} ({len(dup_groups)} duplicate, {len(groups) - len(dup_groups)} singleton)")
    classed = sum(1 for it in items if "class" in it)
    print(f"  classed items:    {classed}/{len(items)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
