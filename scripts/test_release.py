import unittest
from release import versions, EDITIONS

class ReleasesTest(unittest.TestCase):
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

if __name__ == "__main__":
    unittest.main()
