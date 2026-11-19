"""python3 -m unittest scripts/test_cutouts.py — cut-out keys match the app's cutPathFor and the DB's path check."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cutouts import cut_path  # noqa: E402

PATH_CHECK = r'^[A-Za-z0-9_-]{1,80}/[A-Za-z0-9_@-]{1,80}\.(webp|jpe?g|png)$'  # product_images_path_check


class Cutouts(unittest.TestCase):
    def test_key_sits_beside_the_photo(self):
        self.assertEqual(cut_path('p1/1730000000000.webp'), 'p1/1730000000000@cut.webp')
        self.assertEqual(cut_path('p1/seed-3-0123456789.webp'), 'p1/seed-3-0123456789@cut.webp')
        self.assertEqual(cut_path('store/1.jpg'), 'store/1@cut.webp')
        self.assertRegex(cut_path('banners/1730000000000.webp'), PATH_CHECK)


if __name__ == '__main__':
    unittest.main()
