import unittest
from unittest.mock import patch
from release import versions, EDITIONS, verify_architectures, required_module_files, verify_modules
from pathlib import Path
from tempfile import TemporaryDirectory

class ReleasesTest(unittest.TestCase):
    def test_base_bundle_rejects_missing_modules(self):
        with TemporaryDirectory() as directory:
            app = Path(directory)
            for relative in required_module_files("combined"):
                file = app / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b"test fixture")
            verify_modules(app, "combined")
            for relative in required_module_files("combined"):
                file = app / relative
                file.unlink()
                with self.assertRaises(AssertionError, msg=relative):
                    verify_modules(app, "combined")
                file.write_bytes(b"test fixture")

    def test_smaller_editions_are_explicit(self):
        self.assertTrue(set(required_module_files("touchbar")) < set(required_module_files("combined")))
        self.assertEqual(required_module_files("touchtab"), [])

    def test_three_independent_update_feeds(self):
        self.assertEqual(set(EDITIONS), {"combined", "touchbar", "touchtab"})
        self.assertEqual(len({item[1] for item in EDITIONS.values()}), 3)

    def test_monotonic_versions(self):
        base, first, later = versions(0), versions(1), versions(100)
        for edition in EDITIONS:
            values = [tuple(map(int, item[edition].split("."))) for item in (base, first, later)]
            self.assertLess(values[0], values[1])
            self.assertLess(values[1], values[2])
        self.assertEqual(base["combined"], base["touchbar"])

    def test_portable_architecture_query(self):
        with patch("release.run", return_value="x86_64 arm64") as command:
            verify_architectures("/path/3£.app/Contents/MacOS/MusicStrip")
            command.assert_called_once_with("xcrun", "lipo", "-archs", "/path/3£.app/Contents/MacOS/MusicStrip")
        with patch("release.run", return_value="arm64"):
            with self.assertRaises(AssertionError):
                verify_architectures("/path/MusicStrip")

if __name__ == "__main__":
    unittest.main()
