import unittest
import tempfile
import shutil
import os
import sqlite3
import time
from datetime import datetime
from unittest.mock import patch

from nas_organizer.database import CacheDB
from nas_organizer.io import fast_hash, safe_copy_atomic
from nas_organizer.metadata import get_file_date
from nas_organizer.core import build_dest_index

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
        h = fast_hash(path)
        self.assertTrue(h.startswith("0_"))
        
    def test_same_content_same_hash(self):
        content = b"identical" * 500
        p1 = self._mkfile("copy1.jpg", content)
        p2 = self._mkfile("copy2.jpg", content)
        self.assertEqual(fast_hash(p1), fast_hash(p2))

class TestCacheDB(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.tmpdir, "test.db")
        self.db = CacheDB(self.db_path)

    def tearDown(self):
        self.db.conn.close()
        shutil.rmtree(self.tmpdir)

    def test_save_and_get_dict(self):
        updates = [("/path/1", "hash1", 100, 1.0)]
        self.db.save_batch(1, updates)
        data = self.db.get_cache_dict(1)
        self.assertIn("/path/1", data)
        self.assertEqual(data["/path/1"]["hash"], "hash1")

    def test_job_queue(self):
        jobs = [("/src", "/dst", "hsh", "PENDING")]
        self.db.enqueue_jobs(jobs)
        pending = self.db.get_pending_jobs()
        self.assertEqual(len(pending), 1)
        self.db.update_job_status("/src", "COPIED")
        pending2 = self.db.get_pending_jobs()
        self.assertEqual(len(pending2), 0)

class TestSafeCopyAtomic(unittest.TestCase):
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
        result = safe_copy_atomic(src, dst)
        self.assertIn("_collision", result)

    def test_atomic_file_transfer(self):
        src = self._mksrc("photo.jpg", b"atomic_data")
        dst = os.path.join(self.dst_dir, "photo.jpg")
        result = safe_copy_atomic(src, dst)
        self.assertEqual(result, dst)
        self.assertTrue(os.path.exists(dst))

if __name__ == '__main__':
    unittest.main()
