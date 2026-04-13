#!/usr/bin/env python3
"""
Comprehensive test suite for organize_nas.py (v3)
"""

import unittest
import tempfile
import shutil
import os
import sqlite3
import time
from datetime import datetime
from unittest.mock import patch

import organize_nas as org

class TestFastHash(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def _mkfile(self, name, content):
        path = os.path.join(self.tmpdir, name)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    def test_empty_file(self):
        path = self._mkfile("empty.jpg", b"")
        h = org.fast_hash(path)
        self.assertTrue(h.startswith("0_"))
        self.assertEqual(len(h.split("_")[1]), 32)
        
    def test_same_content_same_hash(self):
        content = b"identical" * 5000
        p1 = self._mkfile("copy1.jpg", content)
        p2 = self._mkfile("copy2.jpg", content)
        self.assertEqual(org.fast_hash(p1), org.fast_hash(p2))

class TestCacheDB(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmpdir, "test.db")
        self.db = org.CacheDB(self.db_path)

    def tearDown(self):
        self.db.conn.close()
        shutil.rmtree(self.tmpdir)

    def test_save_and_get_dict(self):
        updates = [("/path/1", "hash1", 100, 1.0)]
        self.db.save_batch(1, updates)
        
        data = self.db.get_cache_dict(1)
        self.assertIn("/path/1", data)
        self.assertEqual(data["/path/1"]["hash"], "hash1")
        
        # Testing isolation by id
        data2 = self.db.get_cache_dict(2)
        self.assertNotIn("/path/1", data2)

    def test_clear(self):
        self.db.save_batch(1, [("/path/1", "hash1", 100, 1.0)])
        self.db.clear()
        data = self.db.get_cache_dict(1)
        self.assertEqual(len(data), 0)

class TestBuildDestIndex(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.db = org.CacheDB(":memory:")

    def tearDown(self):
        self.db.conn.close()
        shutil.rmtree(self.tmpdir)

    def _mkfile(self, relpath, content=b"test"):
        path = os.path.join(self.tmpdir, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    def test_indexes_files(self):
        self._mkfile("2024/04/17/2024-04-17_001.jpg", b"photo1")
        self._mkfile("2024/04/17/2024-04-17_002.jpg", b"photo2")
        hash_idx, seq_idx, dup_seq_idx = org.build_dest_index(self.tmpdir, self.db)
        self.assertEqual(len(hash_idx), 2)
        self.assertEqual(seq_idx["2024-04-17"], 2)

    def test_duplicate_folder_tracking(self):
        self._mkfile("2024/04/17/2024-04-17_001.jpg", b"photo1")
        self._mkfile("Duplicate/2024/04/17/2024-04-17_005.jpg", b"dup1")
        hash_idx, seq_idx, dup_seq_idx = org.build_dest_index(self.tmpdir, self.db)
        
        self.assertEqual(len(hash_idx), 2)
        self.assertEqual(seq_idx["2024-04-17"], 1)
        self.assertEqual(dup_seq_idx["2024-04-17"], 5)

    def test_rebuild_cache_flag_clears_db(self):
        self._mkfile("2024/04/17/2024-04-17_001.jpg", b"photo1")
        updates = [("/fake/path", "fake_hash", 0, 0.0)]
        self.db.save_batch(2, updates)
        
        # Using rebuild=True should clear the old cache entry
        hash_idx, _, _ = org.build_dest_index(self.tmpdir, self.db, rebuild=True)
        self.assertNotIn("fake_hash", hash_idx)
        self.assertEqual(len(hash_idx), 1)

class TestHashSourceFiles(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.db = org.CacheDB(":memory:")

    def tearDown(self):
        self.db.conn.close()
        shutil.rmtree(self.tmpdir)
        
    def _mkfile(self, name, content=b"test"):
        path = os.path.join(self.tmpdir, name)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    def test_hashes_all_files(self):
        files = [self._mkfile(f"photo_{i}.jpg", f"content_{i}".encode()) for i in range(5)]
        hashes = org.hash_source_files(files, self.db)
        self.assertEqual(len(hashes), 5)
        self.assertTrue(all(h is not None for h in hashes.values()))

    def test_cache_hits(self):
        f = self._mkfile(f"photo.jpg", b"cache_me")
        # First pass inserts cache
        org.hash_source_files([f], self.db)
        # Second pass retrieves it naturally (which we can observe indirectly by speed, but functionality is same)
        hashes = org.hash_source_files([f], self.db)
        self.assertEqual(len(hashes), 1)

class TestGetFileDate(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def _mkfile(self, name, content=b"test"):
        path = os.path.join(self.tmpdir, name)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    def test_valid_filename(self):
        path = self._mkfile("IMG_20200704_120000.jpg")
        dt = org.get_file_date(path)
        self.assertEqual(dt.year, 2020)
        self.assertEqual(dt.month, 7)
        self.assertEqual(dt.day, 4)

    @patch('organize_nas.HAS_EXIFREAD', False)
    @patch('organize_nas.get_date_mdls')
    def test_fallback_mdls(self, mock_mdls):
        mock_mdls.return_value = datetime(2022, 5, 10)
        path = self._mkfile("unparsed_name.jpg")
        dt = org.get_file_date(path)
        self.assertEqual(dt.year, 2022)

    @patch('organize_nas.HAS_EXIFREAD', False)
    @patch('organize_nas.get_date_mdls')
    def test_fallback_mtime(self, mock_mdls):
        mock_mdls.return_value = None
        path = self._mkfile("_DSC0025.JPG")
        target_ts = datetime(2015, 6, 20).timestamp()
        os.utime(path, (target_ts, target_ts))
        dt = org.get_file_date(path)
        self.assertEqual(dt.year, 2015)

class TestSafeCopy(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.src_dir = os.path.join(self.tmpdir, "src")
        self.dst_dir = os.path.join(self.tmpdir, "dst")
        os.makedirs(self.src_dir)

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def _mksrc(self, name, content=b"test"):
        path = os.path.join(self.src_dir, name)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    def test_collision_renames(self):
        src = self._mksrc("photo.jpg", b"new_data")
        dst = os.path.join(self.dst_dir, "photo.jpg")
        os.makedirs(self.dst_dir)
        with open(dst, 'w') as f:
            f.write("existing")
        result = org.safe_copy(src, dst)
        self.assertIn("_collision", result)

class TestEndToEndDryRun(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.src = os.path.join(self.tmpdir, "source")
        self.dst = os.path.join(self.tmpdir, "dest")
        os.makedirs(self.src)
        os.makedirs(self.dst)
        self.db = org.CacheDB(os.path.join(self.dst, ".test_cache.db"))

    def tearDown(self):
        self.db.conn.close()
        shutil.rmtree(self.tmpdir)

    def _mksrc(self, name, content=b"test"):
        path = os.path.join(self.src, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    def _mkdst(self, relpath, content=b"existing"):
        path = os.path.join(self.dst, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(content)
        return path

    @patch('organize_nas.get_file_date')
    def test_e2e_classification(self, mock_date):
        mock_date.return_value = datetime(2024, 4, 17)
        self._mksrc("IMG_20240417_1.jpg", b"unique_content_1")
        self._mksrc("IMG_20240417_2.jpg", b"unique_content_2")
        self._mksrc("duplicate.jpg", b"unique_content_1") # internal source dup
        self._mkdst("2024/04/17/2024-04-17_001.jpg", b"unique_content_2") # already in dst

        src_files = org.collect_source_files(self.src)
        dest_hash, dest_seq, _ = org.build_dest_index(self.dst, self.db)
        src_hashes = org.hash_source_files(src_files, self.db)

        seen = {}
        new_count, dup_count, skip_count = 0, 0, 0

        for path in src_files:
            h = src_hashes.get(path)
            if h in dest_hash:
                skip_count += 1
            elif h in seen:
                dup_count += 1
            else:
                seen[h] = path
                new_count += 1

        self.assertEqual(skip_count, 1)
        self.assertEqual(new_count, 1)
        self.assertEqual(dup_count, 1)

if __name__ == '__main__':
    unittest.main()
