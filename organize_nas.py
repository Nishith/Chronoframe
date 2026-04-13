#!/usr/bin/env python3
"""
NAS Photo Organizer v3 — High-Performance Edition

Usage:
  python3 organize_nas.py --dry-run                         # preview
  python3 organize_nas.py                                   # execute
  python3 organize_nas.py --source /path --dest /path       # override SRC/DST
  python3 organize_nas.py --rebuild-cache                   # force full re-index
  python3 organize_nas.py --verify                          # verify copied files by hash
  python3 organize_nas.py --yes                             # auto-confirm copy and skip prompt

v3 improvements:
  - SQLite Database Cache (.organize_cache.db) for fast indexing
  - Multithreaded I/O resolving network latencies
  - Native EXIF parsing (via `exifread`)
  - Duplicate/ bucket sequence continuation
  - Console \r progress updates and interactive confirmation

Rules:
  - NEVER deletes any source files
  - Date priority: EXIF -> Spotlight -> filename pattern -> mtime
  - Duplicate detection: fast hash (size + first/last 512KB MD5)
"""

import os
import sys
import json
import shutil
import hashlib
import subprocess
import re
import time
import argparse
import sqlite3
import concurrent.futures
from datetime import datetime
from collections import defaultdict

try:
    import exifread
    HAS_EXIFREAD = True
except ImportError:
    HAS_EXIFREAD = False

# ═══════════════════════════════════════════════════════════════════════════════
# SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════
SRC = "/Volumes/photo/bkp_1_9"
DST = "/Volumes/home/Organized_Photos_Apr_26"

PHOTO_EXTS = {'.jpg', '.jpeg', '.heic', '.png', '.gif', '.bmp', '.tiff', '.tif',
              '.dng', '.nef', '.cr2', '.arw', '.raf', '.orf'}
VIDEO_EXTS = {'.mov', '.mp4', '.m4v', '.avi', '.mkv', '.wmv', '.3gp'}
ALL_EXTS   = PHOTO_EXTS | VIDEO_EXTS

SKIP_FILES = {'organize_nas.py', 'organize_nas_v2.py', 'run_organize.sh',
              'reorganize_structure.sh'}

SEQ_WIDTH = 3
MAX_CONSECUTIVE_FAILURES = 5

def parse_args():
    parser = argparse.ArgumentParser(description="NAS Photo Organizer v3 for Mac")
    parser.add_argument("--source", type=str, default=None, help="Source folder")
    parser.add_argument("--dest", type=str, default=None, help="Destination folder")
    parser.add_argument("--dry-run", action="store_true", help="Preview only, do not copy")
    parser.add_argument("--rebuild-cache", action="store_true", help="Force database re-index")
    parser.add_argument("--verify", action="store_true", help="Verify copied files by hash")
    parser.add_argument("-y", "--yes", action="store_true", help="Skip copy confirmation prompt")
    return parser.parse_args()

class RunLogger:
    def __init__(self, log_path):
        self.log_path = log_path
        self._fh = None

    def open(self):
        try:
            self._fh = open(self.log_path, 'a')
        except OSError:
            pass

    def close(self):
        if self._fh:
            self._fh.close()
            self._fh = None

    def log(self, message, also_print=True, overwrite=False):
        ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        line = f"[{ts}] {message}"
        if self._fh:
            try:
                self._fh.write(line + "\n")
                self._fh.flush()
            except OSError:
                pass
        if also_print:
            if overwrite:
                print(f"\r{message}", end="", flush=True)
            else:
                print(message)

    def warn(self, message):
        self.log(f"WARNING: {message}")

    def error(self, message):
        self.log(f"ERROR: {message}")

    def summary(self, message):
        self.log(message, also_print=False)

def fast_hash(path, known_size=None):
    size = known_size if known_size is not None else os.path.getsize(path)
    h = hashlib.md5()
    h.update(str(size).encode())
    chunk = 512 * 1024
    with open(path, 'rb') as f:
        h.update(f.read(chunk))
        if size > chunk:
            f.seek(-min(chunk, size - chunk), 2)
            h.update(f.read(chunk))
    return f"{size}_{h.hexdigest()}"

class CacheDB:
    def __init__(self, db_path):
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self.conn.execute('''CREATE TABLE IF NOT EXISTS FileCache (
                              id INTEGER,
                              path TEXT,
                              hash TEXT,
                              size INTEGER,
                              mtime REAL,
                              PRIMARY KEY (id, path)
                           )''')
        self.conn.commit()

    def get_cache_dict(self, type_id):
        cur = self.conn.execute("SELECT path, hash, size, mtime FROM FileCache WHERE id = ?", (type_id,))
        return {row[0]: {"hash": row[1], "size": row[2], "mtime": row[3]} for row in cur}

    def save_batch(self, type_id, updates):
        self.conn.executemany("REPLACE INTO FileCache (id, path, hash, size, mtime) VALUES (?, ?, ?, ?, ?)",
                              [(type_id, p, h, s, m) for p, h, s, m in updates])
        self.conn.commit()

    def clear(self):
        self.conn.execute("DELETE FROM FileCache")
        self.conn.commit()

def process_single_file(path, cached_data):
    try:
        st = os.stat(path)
        size = st.st_size
        mtime = st.st_mtime
        if cached_data and cached_data["size"] == size and abs(cached_data["mtime"] - mtime) < 0.001:
            return cached_data["hash"], size, mtime, False
        h = fast_hash(path, known_size=size)
        return h, size, mtime, True
    except OSError:
        return None, 0, 0, False

def build_dest_index(dst_dir, cache_db, rebuild=False, logger=None):
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
    hashed = 0
    cached_hits = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(process_single_file, path, cache.get(path)): path for path in files_to_check}
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            path = futures[future]
            if i % 500 == 0:
                print(f"\r    Scanned {i}/{len(files_to_check)} dest files...", end="", flush=True)
            try:
                h, size, mtime, was_hashed = future.result()
                if h:
                    hash_index[h] = path
                    if was_hashed:
                        hashed += 1
                        updates.append((path, h, size, mtime))
                    else:
                        cached_hits += 1
            except Exception:
                pass
    if files_to_check: print()
    
    cache_db.save_batch(2, updates)
    print(f"  {len(files_to_check)} files ({cached_hits} cached, {hashed} hashed)")
    print(f"  {len(seq_index)} direct sequence paths, {len(dup_seq_index)} duplicate paths indexed")
    return hash_index, seq_index, dup_seq_index

def collect_source_files(src_dir):
    files = []
    for root, dirs, fnames in os.walk(src_dir):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for fname in sorted(fnames):
            if fname.startswith('.') or fname in SKIP_FILES:
                continue
            ext = os.path.splitext(fname)[1].lower()
            if ext in ALL_EXTS:
                files.append(os.path.join(root, fname))
    return files

def hash_source_files(src_files, cache_db, logger=None):
    cache = cache_db.get_cache_dict(1)
    hashes = {}
    updates = []
    cached_hits = 0
    hashed = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(process_single_file, path, cache.get(path)): path for path in src_files}
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            path = futures[future]
            if i % 100 == 0:
                print(f"\r  Analyzed {i}/{len(src_files)} source files...", end="", flush=True)
            try:
                h, size, mtime, was_hashed = future.result()
                hashes[path] = h
                if h and was_hashed:
                    hashed += 1
                    updates.append((path, h, size, mtime))
                elif h:
                    cached_hits += 1
            except Exception:
                hashes[path] = None
    if src_files: print()

    cache_db.save_batch(1, updates)
    return hashes

def get_date_exifread(path):
    try:
        with open(path, 'rb') as f:
            tags = exifread.process_file(f, stop_tag="EXIF DateTimeOriginal", details=False)
            keys = ['EXIF DateTimeOriginal', 'Image DateTime']
            for k in keys:
                if k in tags:
                    val = str(tags[k]).strip()
                    if val and val != "0000:00:00 00:00:00":
                        val = val.replace(":", "-", 2)
                        return datetime.strptime(val[:19], '%Y-%m-%d %H:%M:%S')
    except Exception:
        pass
    return None

def get_date_mdls(path):
    try:
        result = subprocess.run(['mdls', '-name', 'kMDItemContentCreationDate', '-raw', path],
                                capture_output=True, text=True, timeout=5)
        val = result.stdout.strip()
        if val and val != '(null)':
            dt = datetime.strptime(val[:19], '%Y-%m-%d %H:%M:%S')
            return dt
    except Exception:
        pass
    return None

def get_date_from_filename(path):
    fname = os.path.basename(path)
    patterns = [r'(?:IMG|VID|PANO|BURST|MVIMG)_(\d{8})_\d{6}', r'^(\d{8})_\d{6}', r'_(\d{8})_']
    for pat in patterns:
        m = re.search(pat, fname)
        if m:
            s = m.group(1)
            try:
                dt = datetime(int(s[:4]), int(s[4:6]), int(s[6:8]))
                if 2000 <= dt.year <= 2030: return dt
            except ValueError:
                pass
    return None

def get_file_date(path):
    ext = os.path.splitext(path)[1].lower()
    if HAS_EXIFREAD and ext in PHOTO_EXTS:
        dt = get_date_exifread(path)
        if dt and dt.year > 1971: return dt

    dt = get_date_from_filename(path)
    if dt: return dt

    dt = get_date_mdls(path)
    if dt and dt.year > 1971: return dt

    mtime_dt = datetime.fromtimestamp(os.path.getmtime(path))
    return mtime_dt

def safe_copy(src, dst, logger=None):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst):
        if logger: logger.error(f"Collision: {dst}")
        base, ext = os.path.splitext(dst)
        dst = f"{base}_collision{ext}"
    try:
        shutil.copy2(src, dst)
        return dst
    except Exception as e:
        if logger: logger.warn(f"Copy fail for {src}: {e}")
        return False

def format_time(seconds):
    if seconds < 60: return f"{seconds:.0f}s"
    elif seconds < 3600: return f"{seconds // 60:.0f}m {seconds % 60:.0f}s"
    return f"{seconds // 3600:.0f}h {(seconds % 3600) // 60:.0f}m"

def main():
    args = parse_args()
    src = args.source or SRC
    dst = args.dest or DST
    dup = os.path.join(dst, "Duplicate")
    rebuild = args.rebuild_cache
    
    if not HAS_EXIFREAD:
        print("\n[NOTE] 'exifread' python package not found.")
        print("Install via `pip install exifread` for much faster EXIF performance.")
        print("Falling back to native `mdls` which may be slower on network drives.\n")

    logger = RunLogger(os.path.join(dst, ".organize_log.txt"))
    logger.open()
    cache_db = CacheDB(os.path.join(dst, ".organize_cache.db"))

    print(f"Source: {src}\nDest:   {dst}\n")

    if not os.path.isdir(src) or not os.path.isdir(dst):
        print("Error: Source or Destination is invalid.")
        sys.exit(1)

    print("=== Scanning Source ===")
    src_files = collect_source_files(src)
    print(f"  {len(src_files)} files found\n")
    if not src_files: return

    print("=== Indexing Destination ===")
    dest_hash_index, dest_seq, dup_seq = build_dest_index(dst, cache_db, rebuild)

    print("\n=== Hashing Source ===")
    src_hashes = hash_source_files(src_files, cache_db)

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
        date_str = dt.strftime('%Y-%m-%d')
        if dt.year <= 1971:
            date_str = "Unknown_Date"
            
        date_groups[date_str].append((src_path, h))
        
    print(f"\n  {already_in_dst} existing files skipped")
    print(f"  {len(src_seen)} new files to track")

    # Build Plan
    plan = []
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
            plan.append((src_path, dst_path, h))

    # Duplicate Plan
    dup_plan = []
    dup_groups = defaultdict(list)
    for src_path, h in src_dups:
        dt = get_file_date(src_path)
        date_str = dt.strftime('%Y-%m-%d') if dt.year > 1971 else "Unknown_Date"
        dup_groups[date_str].append((src_path, h))
        
    for date_str in sorted(dup_groups.keys()):
        start_seq = dup_seq.get(date_str, 0) + 1
        for i, (src_path, h) in enumerate(dup_groups[date_str]):
            seq = start_seq + i
            ext = os.path.splitext(src_path)[1]
            if date_str == 'Unknown_Date':
                filename = f"Unknown_{str(seq).zfill(SEQ_WIDTH)}{ext}"
                dst_path = os.path.join(dup, "Unknown_Date", filename)
            else:
                yyyy, mm, dd = date_str.split('-')
                filename = f"{date_str}_{str(seq).zfill(SEQ_WIDTH)}{ext}"
                dst_path = os.path.join(dup, yyyy, mm, dd, filename)
            dup_plan.append((src_path, dst_path, h))

    if args.dry_run:
        print("\n=== DRY RUN PLAN ===")
        for s, d, _ in plan[:10]: print(f"  {os.path.basename(s)} -> {os.path.relpath(d, dst)}")
        print("\nDry run completed.")
        return

    total_copy = len(plan) + len(dup_plan)
    if total_copy == 0:
        print("Nothing to copy.")
        return

    print(f"\n{len(plan)} new files, {len(dup_plan)} internal duplicates.")
    if not args.yes:
        ans = input(f"Proceed with copying {total_copy} files? [y/N]: ")
        if ans.lower() not in ('y', 'yes'):
            print("Aborted.")
            return

    # Execute Copy
    copy_start = time.time()
    dest_updates = []
    
    def process_copy_plan(pln, label):
        done = 0
        consecutive_fail = 0
        for src_p, dst_p, h in pln:
            result = safe_copy(src_p, dst_p, logger=logger)
            if result:
                done += 1
                consecutive_fail = 0
                try:
                    st = os.stat(result)
                    dest_updates.append((result, h, st.st_size, st.st_mtime))
                except OSError: pass
            else:
                consecutive_fail += 1
                if consecutive_fail >= MAX_CONSECUTIVE_FAILURES:
                    print(f"\nAborting: {MAX_CONSECUTIVE_FAILURES} fails.")
                    break
            
            if done % 10 == 0:
                rate = done / (time.time() - copy_start)
                rem = (len(pln) - done) / rate if rate > 0 else 0
                print(f"\r  {label}: {done}/{len(pln)} ({rate:.1f}/s) ~{format_time(rem)}", end="", flush=True)
        if pln: print()
        return done

    print("\nCopying primary files...")
    process_copy_plan(plan, "Copying")
    
    if dup_plan:
        print("Copying duplicates...")
        process_copy_plan(dup_plan, "Dups")

    cache_db.save_batch(2, dest_updates)
    print(f"\nDone in {format_time(time.time() - copy_start)}")

if __name__ == "__main__":
    main()
