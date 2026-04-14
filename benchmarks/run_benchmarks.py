#!/usr/bin/env python3
"""
Synthetic benchmark harness for the Python reference engine.
"""

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from chronoframe.core import build_dest_index
from chronoframe.database import CacheDB
from chronoframe.io import process_single_file
from chronoframe.metadata import get_file_date


def parse_args():
    parser = argparse.ArgumentParser(description="Chronoframe synthetic benchmark harness")
    parser.add_argument("--source-count", type=int, default=250, help="Synthetic source-file count")
    parser.add_argument("--dest-count", type=int, default=400, help="Synthetic destination-file count")
    parser.add_argument("--workers", type=int, default=8, help="Thread worker count")
    parser.add_argument("--file-size-kb", type=int, default=64, help="Synthetic file size in KB")
    parser.add_argument("--keep", action="store_true", help="Keep the generated temp tree for inspection")
    return parser.parse_args()


def make_tree(root, count, size_kb, prefix):
    os.makedirs(root, exist_ok=True)
    payload = (prefix.encode("utf-8") * 1024)[:1024] * size_kb
    created = []

    for index in range(count):
        month = (index % 12) + 1
        day = (index % 28) + 1
        hour = index % 24
        minute = (index * 3) % 60
        second = (index * 7) % 60
        folder = os.path.join(root, f"batch_{index // 100:03d}")
        os.makedirs(folder, exist_ok=True)
        filename = f"VID_2024{month:02d}{day:02d}_{hour:02d}{minute:02d}{second:02d}_{index:05d}.mov"
        path = os.path.join(folder, filename)
        with open(path, "wb") as handle:
            handle.write(payload)
        created.append(path)

    return created


def benchmark_hashing(paths, workers):
    start = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        list(executor.map(lambda path: process_single_file(path, None), paths))
    elapsed = time.perf_counter() - start
    return {
        "seconds": elapsed,
        "files_per_second": 0 if elapsed == 0 else len(paths) / elapsed,
    }


def benchmark_classification(paths, workers):
    start = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        list(executor.map(get_file_date, paths))
    elapsed = time.perf_counter() - start
    return {
        "seconds": elapsed,
        "files_per_second": 0 if elapsed == 0 else len(paths) / elapsed,
    }


def benchmark_destination_indexing(dest_root, workers):
    db_path = os.path.join(dest_root, ".organize_cache.db")
    cache_db = CacheDB(db_path)
    try:
        start = time.perf_counter()
        build_dest_index(dest_root, cache_db, workers=workers, fast_dest=False)
        cold_elapsed = time.perf_counter() - start

        start = time.perf_counter()
        build_dest_index(dest_root, cache_db, workers=workers, fast_dest=True)
        fast_elapsed = time.perf_counter() - start
    finally:
        cache_db.close()

    return {
        "cold_seconds": cold_elapsed,
        "fast_dest_seconds": fast_elapsed,
    }


def benchmark_preview(repo_root, source_root, dest_root, workers):
    command = [
        "python3",
        os.path.join(repo_root, "chronoframe.py"),
        "--source",
        source_root,
        "--dest",
        dest_root,
        "--dry-run",
        "--fast-dest",
        "--workers",
        str(workers),
        "--yes",
        "--json",
    ]

    start = time.perf_counter()
    result = subprocess.run(
        command,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "CHRONOFRAME_NONINTERACTIVE": "1"},
    )
    elapsed = time.perf_counter() - start

    complete_events = []
    for line in result.stdout.splitlines():
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if payload.get("type") == "complete":
            complete_events.append(payload)

    return {
        "seconds": elapsed,
        "exit_code": result.returncode,
        "complete_events": len(complete_events),
    }


def main():
    args = parse_args()
    temp_root = tempfile.mkdtemp(prefix="chronoframe-bench-")

    try:
        source_root = os.path.join(temp_root, "source")
        dest_root = os.path.join(temp_root, "dest")
        source_paths = make_tree(source_root, args.source_count, args.file_size_kb, "src")
        make_tree(dest_root, args.dest_count, args.file_size_kb, "dst")

        summary = {
            "inputs": {
                "source_count": args.source_count,
                "dest_count": args.dest_count,
                "workers": args.workers,
                "file_size_kb": args.file_size_kb,
            },
            "hashing": benchmark_hashing(source_paths, args.workers),
            "classification": benchmark_classification(source_paths, args.workers),
            "destination_indexing": benchmark_destination_indexing(dest_root, args.workers),
            "preview": benchmark_preview(REPO_ROOT, source_root, dest_root, args.workers),
        }

        print(json.dumps(summary, indent=2))
    finally:
        if args.keep:
            print(json.dumps({"kept_temp_root": temp_root}))
        else:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    main()
