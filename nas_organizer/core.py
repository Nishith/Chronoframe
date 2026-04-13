import os
import sys
import time
import argparse
import concurrent.futures
from datetime import datetime
from collections import defaultdict

from .database import CacheDB
from .io import safe_copy_atomic, process_single_file
from .metadata import get_file_date, ALL_EXTS, SKIP_FILES, HAS_EXIFREAD

SRC = "/Volumes/home/Desktop/NAS-mock/source" # Using dummy defaults fallback just in case
DST = "/Volumes/home/Organized_Photos_Apr_26"
SEQ_WIDTH = 3
MAX_CONSECUTIVE_FAILURES = 5

def parse_args():
    parser = argparse.ArgumentParser(description="NAS Photo Organizer v3 - L7 Edition")
    parser.add_argument("--source", type=str, default=None, help="Source folder")
    parser.add_argument("--dest", type=str, default=None, help="Destination folder")
    parser.add_argument("--dry-run", action="store_true", help="Preview only, do not copy")
    parser.add_argument("--rebuild-cache", action="store_true", help="Force database re-index")
    parser.add_argument("-y", "--yes", action="store_true", help="Skip copy confirmation prompt")
    return parser.parse_args()

def build_dest_index(dst_dir, cache_db, rebuild=False):
    import re
    if rebuild:
        cache_db.clear()
        
    cache = cache_db.get_cache_dict(2)
    files_to_check = []
    
    seq_index = defaultdict(int)
    dup_seq_index = defaultdict(int)
    seq_pattern = re.compile(r'^(\d{4}-\d{2}-\d{2})_(\d+)')
    dup_dir = os.path.join(dst_dir, "Duplicate")

    for root, dirs, fnames in os.walk(dst_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in fnames:
            if fname.startswith('.') or fname in SKIP_FILES or not fname.endswith(tuple(ALL_EXTS)):
                continue
            path = os.path.join(root, fname)
            files_to_check.append(path)

            m = seq_pattern.match(fname)
            if m:
                date_str, seq = m.group(1), int(m.group(2))
                if path.startswith(dup_dir):
                    if seq > dup_seq_index[date_str]: dup_seq_index[date_str] = seq
                else:
                    if seq > seq_index[date_str]: seq_index[date_str] = seq

    hash_index = {}
    updates = []
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(process_single_file, path, cache.get(path)): path for path in files_to_check}
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            path = futures[future]
            if i % 100 == 0:
                print(f"\r    Scanned {i}/{len(files_to_check)} dest files...", end="", flush=True)
            try:
                h, size, mtime, was_hashed = future.result()
                if h:
                    hash_index[h] = path
                    if was_hashed:
                        updates.append((path, h, size, mtime))
            except Exception:
                pass
    if files_to_check: print()
    cache_db.save_batch(2, updates)
    return hash_index, seq_index, dup_seq_index

def format_time(seconds):
    if seconds < 60: return f"{seconds:.0f}s"
    elif seconds < 3600: return f"{seconds // 60:.0f}m {seconds % 60:.0f}s"
    return f"{seconds // 3600:.0f}h {(seconds % 3600) // 60:.0f}m"

def main():
    args = parse_args()
    src = args.source or "/Volumes/photo/bkp_1_9"
    dst = args.dest or DST
    dup = os.path.join(dst, "Duplicate")
    rebuild = args.rebuild_cache
    
    if not HAS_EXIFREAD:
        print("\n[NOTE] 'exifread' python package not found.")
        print("Falling back to native `mdls` which may be slower on network drives.\n")

    cache_db = CacheDB(os.path.join(dst, ".organize_cache.db"))

    print(f"Source: {src}\nDest:   {dst}\n")

    if not os.path.isdir(src) or not os.path.isdir(dst):
        print("Error: Source or Destination is invalid.")
        sys.exit(1)

    print("=== Checking Resumable Queue ===")
    pending_jobs = cache_db.get_pending_jobs()
    if pending_jobs:
        print(f"Found {len(pending_jobs)} paused jobs in Queue!")
        if not args.dry_run:
            execute_jobs(pending_jobs, cache_db)
            print("Queue cleared.")
            return

    print("=== Scanning Source ===")
    src_files = []
    for root, dirs, fnames in os.walk(src):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for fname in sorted(fnames):
            if fname.startswith('.') or fname in SKIP_FILES: pass
            elif os.path.splitext(fname)[1].lower() in ALL_EXTS:
                src_files.append(os.path.join(root, fname))
    
    if not src_files: return

    print("=== Indexing Destination ===")
    dest_hash_index, dest_seq, dup_seq = build_dest_index(dst, cache_db, rebuild)

    print("\n=== Hashing Source ===")
    src_cache = cache_db.get_cache_dict(1)
    src_hashes = {}
    src_updates = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(process_single_file, path, src_cache.get(path)): path for path in src_files}
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            path = futures[future]
            if i % 100 == 0:
                print(f"\r  Analyzed {i}/{len(src_files)} source files...", end="", flush=True)
            try:
                h, size, mtime, was_hashed = future.result()
                src_hashes[path] = h
                if h and was_hashed:
                    src_updates.append((path, h, size, mtime))
            except Exception:
                pass
    if src_files: print()
    cache_db.save_batch(1, src_updates)

    date_groups = defaultdict(list)
    src_dups = []
    already_in_dst = 0
    src_seen = {}
    
    print("\n=== Classifying Dates ===")
    for i, src_path in enumerate(src_files, 1):
        if i % 100 == 0:
            print(f"\r  Parsing dates: {i}/{len(src_files)}...", end="", flush=True)
            
        h = src_hashes.get(src_path)
        if not h: continue

        if h in dest_hash_index:
            already_in_dst += 1
            continue

        if h in src_seen:
            src_dups.append((src_path, h))
            continue

        src_seen[h] = src_path
        dt = get_file_date(src_path)
        date_str = dt.strftime('%Y-%m-%d') if dt.year > 1971 else "Unknown_Date"
        date_groups[date_str].append((src_path, h))
        
    print(f"\n  {already_in_dst} existing files skipped")

    jobs_to_insert = []
    for date_str in sorted(date_groups.keys()):
        start_seq = dest_seq.get(date_str, 0) + 1
        for i, (src_path, h) in enumerate(date_groups[date_str]):
            seq = start_seq + i
            ext = os.path.splitext(src_path)[1]
            if date_str == 'Unknown_Date':
                filename = f"Unknown_{str(seq).zfill(SEQ_WIDTH)}{ext}"
                dst_path = os.path.join(dst, "Unknown_Date", filename)
            else:
                yyyy, mm, dd = date_str.split('-')
                filename = f"{date_str}_{str(seq).zfill(SEQ_WIDTH)}{ext}"
                dst_path = os.path.join(dst, yyyy, mm, dd, filename)
            jobs_to_insert.append((src_path, dst_path, h, 'PENDING'))

    for src_path, h in src_dups:
        dt = get_file_date(src_path)
        date_str = dt.strftime('%Y-%m-%d') if dt.year > 1971 else "Unknown_Date"
        start_seq = dup_seq.get(date_str, 0) + 1
        dup_seq[date_str] += 1
        ext = os.path.splitext(src_path)[1]
        
        if date_str == 'Unknown_Date':
            filename = f"Unknown_{str(start_seq).zfill(SEQ_WIDTH)}{ext}"
            dst_path = os.path.join(dup, "Unknown_Date", filename)
        else:
            yyyy, mm, dd = date_str.split('-')
            filename = f"{date_str}_{str(start_seq).zfill(SEQ_WIDTH)}{ext}"
            dst_path = os.path.join(dup, yyyy, mm, dd, filename)
        jobs_to_insert.append((src_path, dst_path, h, 'PENDING'))

    if args.dry_run:
        print("\n=== DRY RUN PLAN ===")
        for s, d, _, _ in jobs_to_insert[:10]: print(f"  {os.path.basename(s)} -> {os.path.relpath(d, dst)}")
        print("\nDry run completed.")
        return

    if sum(1 for j in jobs_to_insert if j[3] == 'PENDING') == 0:
        print("Nothing to copy.")
        return

    print(f"\n{len(jobs_to_insert)} total files ready for queue.")
    if not args.yes:
        ans = input(f"Commit to database and initiate atomic copies? [y/N]: ")
        if ans.lower() not in ('y', 'yes'):
            return

    cache_db.enqueue_jobs(jobs_to_insert)
    
    pending_jobs = cache_db.get_pending_jobs()
    execute_jobs(pending_jobs, cache_db)

def execute_jobs(pending_jobs, cache_db):
    print(f"\nProcessing {len(pending_jobs)} queued jobs atomically...")
    copy_start = time.time()
    dest_updates = []
    
    done = 0
    consecutive_fail = 0
    total = len(pending_jobs)
    
    for src_p, dst_p, h in pending_jobs:
        try:
            result = safe_copy_atomic(src_p, dst_p)
            done += 1
            consecutive_fail = 0
            cache_db.update_job_status(src_p, 'COPIED')
            st = os.stat(result)
            dest_updates.append((result, h, st.st_size, st.st_mtime))
        except Exception as e:
            cache_db.update_job_status(src_p, 'FAILED')
            consecutive_fail += 1
            if consecutive_fail >= MAX_CONSECUTIVE_FAILURES:
                print(f"\nAborting Sequence: Network fault tolerance breached.")
                break
        
        if done % 5 == 0:
            rate = done / (time.time() - copy_start)
            rem = (total - done) / rate if rate > 0 else 0
            print(f"\r  Progress: {done}/{total} ({rate:.1f}/s) ~{format_time(rem)}", end="", flush=True)

    if total: print()
    cache_db.save_batch(2, dest_updates)
    print(f"\nQueue processed in {format_time(time.time() - copy_start)}")
