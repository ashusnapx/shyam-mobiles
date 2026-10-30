"""python3 -m unittest scripts/test_seed_photos.py — checks the seed photo naming, sizing, local-only guard and mapping."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from seed_photos import MAPPING, bbox, entry, local_api, seed_path, square  # noqa: E402

PATH_CHECK = r'^[A-Za-z0-9_-]{1,80}/[A-Za-z0-9_@-]{1,80}\.(webp|jpe?g|png)$'  # product_images_path_check


class SeedPhotos(unittest.TestCase):
    def test_paths_pass_the_db_check_and_match_the_app_thumb_name(self):
        pid, digest = '931b1d64-1c41-4d4a-8751-0101cd02cdcc', '0123456789'
        full, thumb = seed_path(pid, 3, digest), seed_path(pid, 3, digest, thumb=True)
        self.assertRegex(full, PATH_CHECK)
        self.assertRegex(thumb, PATH_CHECK)
        self.assertEqual(full[:-len('.webp')] + '@thumb.webp', thumb)  # supabase.dart thumbPathFor

    def test_square_canvas_keeps_a_six_percent_margin_and_never_upscales(self):
        self.assertEqual(square(712, 1536), (1600, 1408))  # tall product: capped at 1600
        self.assertEqual(square(360, 744), (845, 744))  # small product: canvas grows, product stays its size
        self.assertEqual(square(880, 660), (1000, 880))

    def test_bbox_finds_the_product_and_ignores_a_stray_pixel(self):
        w, h = 10, 8
        img = bytearray([255] * (w * h))
        for y in range(2, 6):
            for x in range(3, 7):
                img[y * w + x] = 250 if x == 3 else 0  # 250 is lighter than INK: counts as background
        img[0] = 0  # one speck in the corner
        self.assertEqual(bbox(bytes(img), w, h), (4, 2, 7, 6))
        self.assertIsNone(bbox(bytes([255] * (w * h)), w, h))

    def test_only_the_local_stack(self):
        self.assertEqual(local_api({'API_URL': 'http://127.0.0.1:54321/'}), 'http://127.0.0.1:54321')
        for url in ('https://lcvnnfrtfbyhevgkeqsa.supabase.co', 'http://localhost:54321', 'http://127.0.0.1.evil.com'):
            with self.assertRaises(SystemExit):
                local_api({'API_URL': url})

    def test_mapping_entries_are_https_urls_with_an_optional_colour(self):
        self.assertEqual(entry('https://x/a.png'), ('https://x/a.png', None))
        self.assertEqual(entry({'url': 'https://x/a.png', 'color': 'Navy'}), ('https://x/a.png', 'Navy'))
        for slug, items in json.loads(MAPPING.read_text()).items():
            self.assertRegex(slug, r'^[a-z0-9-]+$')
            urls = [entry(i)[0] for i in items]
            self.assertTrue(all(u.startswith('https://') for u in urls), slug)
            self.assertEqual(len(urls), len(set(urls)), slug)


if __name__ == '__main__':
    unittest.main()
