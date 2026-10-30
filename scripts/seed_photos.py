#!/usr/bin/env python3
"""Temporary catalogue photos for the LOCAL stack: brand images from scripts/seed_photos.json.

  python3 scripts/seed_photos.py            # download, convert and upload; skips products that already have seed photos
  python3 scripts/seed_photos.py --remove   # delete every seed-* photo and its product_images row

The brands own these images: they live only in local storage, never in git, and go before launch
(the shop's own photos replace them). Each photo is flattened on white, its near-white border trimmed, and
centred on a square white canvas with a 6% margin, so every product photo has the same shape. Files follow the admin
upload (app/lib/features/admin/data): <product_id>/seed-<n>-<hash>.webp (<= 1600 px, q80) plus @thumb.webp
(<= 400 px, q70), cached a year; the hash is of the photo, so a re-processed photo gets a new key, never a stale cache.
Mapping entries are a URL (shows for every colour) or {"url": ..., "color": <variants.attributes->>'color'>}.
Local stack only: it refuses any API URL that isn't 127.0.0.1. Never prints a key.
"""
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dev_setup import ROOT, status  # noqa: E402

MAPPING = ROOT / 'scripts' / 'seed_photos.json'
# Downloads are untrusted: each goes into its own new dir under the system temp folder, outside the repo, and is only
# passed to ffmpeg/cwebp.
WORK = Path(tempfile.gettempdir()) / 'shyam-seed-photos'
BUCKET = 'product-images'
MAX_BYTES = 15 * 1024 * 1024  # photos.dart maxPhotoBytes
FULL, THUMB = (1600, 80), (400, 70)  # photos.dart fullSide/fullQuality; thumb asked for at 400 (the app's is 480)
MARGIN = 0.06  # white space on each side of the trimmed product
INK, PROBE = 246, 512  # a pixel darker than INK (0-255, on white) is product; the box is found at PROBE px
CACHE = 'max-age=31536000'  # admin.dart cacheControl '31536000'
UA = 'Mozilla/5.0'  # some brand CDNs refuse a full browser UA string from curl-like clients


def local_api(env: dict) -> str:
    api = env['API_URL'].rstrip('/')
    if urllib.parse.urlparse(api).hostname != '127.0.0.1':
        raise SystemExit(f'refusing: {api} is not the local stack')
    return api


def square(w: int, h: int, side: int = FULL[0]) -> tuple[int, int]:
    """(canvas, inner): a square canvas of at most `side` px, the trimmed w x h fitted inside with MARGIN each side; never upscales."""
    canvas = min(side, round(max(w, h) / (1 - 2 * MARGIN)))
    return canvas, round(canvas * (1 - 2 * MARGIN))


def seed_path(product_id: str, n: int, digest: str, thumb: bool = False) -> str:
    return f"{product_id}/seed-{n}-{digest}{'@thumb' if thumb else ''}.webp"


def entry(item) -> tuple[str, str | None]:
    return (item, None) if isinstance(item, str) else (item['url'], item.get('color'))


class Api:
    def __init__(self, env: dict):
        self.base, key = local_api(env), env.get('SERVICE_ROLE_KEY') or env['SECRET_KEY']
        self.auth = {'apikey': key, 'Authorization': f'Bearer {key}'}

    def call(self, method: str, path: str, body=None, headers: dict | None = None):
        """JSON in and out; a bytes body is sent as is (the caller sets its Content-Type)."""
        data, h = body, {**self.auth, **(headers or {})}
        if body is not None and not isinstance(body, bytes):
            data, h = json.dumps(body).encode(), {'Content-Type': 'application/json', **h}
        req = urllib.request.Request(f'{self.base}{path}', data=data, method=method, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'{method} {path.split("?")[0]}: {e.code} {e.read().decode()[:200]}') from None
        return json.loads(raw) if raw.strip() else None

    def upload(self, path: str, data: bytes) -> None:
        self.call('POST', f'/storage/v1/object/{BUCKET}/{path}', data,
                  {'Content-Type': 'image/webp', 'cache-control': CACHE, 'x-upsert': 'true'})

    def remove(self, paths: list[str]) -> None:
        if paths:
            self.call('DELETE', f'/storage/v1/object/{BUCKET}', {'prefixes': paths})

    def seed_objects(self, product_id: str) -> list[str]:
        found = self.call('POST', f'/storage/v1/object/list/{BUCKET}', {'prefix': f'{product_id}/', 'search': 'seed-', 'limit': 1000})
        return [f"{product_id}/{o['name']}" for o in found or [] if o['name'].startswith('seed-')]


def download(url: str) -> Path:
    d = Path(tempfile.mkdtemp(dir=WORK))  # new empty dir per file
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'image/*'})
    with urllib.request.urlopen(req, timeout=30) as r:
        ctype = r.headers.get_content_type()
        if not ctype.startswith('image/'):
            raise ValueError(f'not an image ({ctype})')
        data = r.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError('over 15 MB')
    f = d / 'original'
    f.write_bytes(data)
    return f


FLAT = 'color=white,format=rgb24[bg];[bg][0]scale2ref[bg2][fg];[bg2][fg]overlay=shortest=1,format=rgb24'  # alpha onto white


def ffmpeg(src: Path, graph: str, *out: str) -> str:
    return subprocess.run(['ffmpeg', '-hide_banner', '-nostdin', '-i', str(src), '-filter_complex', graph, '-frames:v', '1', *out],
                          capture_output=True, text=True, check=True, cwd=WORK).stderr


def size_of(f: Path) -> tuple[int, int]:
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
                          '-of', 'csv=p=0', str(f)], capture_output=True, text=True, check=True, cwd=WORK).stdout
    w, h = out.strip().split('\n')[0].split(',')[:2]
    return int(w), int(h)


def bbox(gray: bytes, w: int, h: int) -> tuple[int, int, int, int] | None:
    """(x0, y0, x1, y1) of the pixels darker than INK, ignoring rows/columns with a single stray pixel."""
    rows = [y for y in range(h) if sum(v < INK for v in gray[y * w:(y + 1) * w]) > 1]
    cols = [x for x in range(w) if sum(v < INK for v in gray[x::w]) > 1]
    return (cols[0], rows[0], cols[-1] + 1, rows[-1] + 1) if rows and cols else None


def squared(src: Path) -> tuple[Path, int]:
    """Flatten on white, trim the near-white border, centre on a white square; returns (PNG next to src, its side)."""
    W, H = size_of(src)
    k = min(1.0, PROBE / max(W, H))  # find the box on a small grey copy: cheap, and the same box scaled back
    dw, dh = max(1, round(W * k)), max(1, round(H * k))
    gray = subprocess.run(['ffmpeg', '-hide_banner', '-nostdin', '-i', str(src), '-filter_complex', f'{FLAT},scale={dw}:{dh},format=gray',
                           '-frames:v', '1', '-f', 'rawvideo', '-'], capture_output=True, check=True, cwd=WORK).stdout
    box = bbox(gray, dw, dh) if len(gray) == dw * dh else None
    if box is None:
        raise ValueError('blank or unreadable image')
    x0, y0 = int(box[0] / k), int(box[1] / k)
    x1, y1 = min(W, math.ceil(box[2] / k)), min(H, math.ceil(box[3] / k))
    canvas, inner = square(x1 - x0, y1 - y0)
    dst = src.with_name('square.png')
    ffmpeg(src, f'{FLAT},crop={x1 - x0}:{y1 - y0}:{x0}:{y0},scale={inner}:{inner}:force_original_aspect_ratio=decrease,'
                f'pad={canvas}:{canvas}:(ow-iw)/2:(oh-ih)/2:white', '-y', str(dst))
    return dst, canvas


def webp(sq: tuple[Path, int], name: str, side: int, quality: int) -> Path:
    src, canvas = sq
    dst = src.with_name(name)
    resize = ['-resize', str(side), str(side)] if side < canvas else []  # square already; never upscale
    # -metadata none drops EXIF/XMP; src is already opaque.
    subprocess.run(['cwebp', '-quiet', '-q', str(quality), '-metadata', 'none', *resize, str(src), '-o', str(dst)],
                   check=True, capture_output=True, cwd=WORK)
    return dst


def seed(api: Api, mapping: dict) -> None:
    products = {p['slug']: p['id'] for p in api.call('GET', '/rest/v1/products?select=id,slug')}
    seeded = {r['product_id'] for r in api.call('GET', '/rest/v1/product_images?select=product_id&path=like.*%2Fseed-*')}
    colors: dict[str, set] = {}
    for v in api.call('GET', '/rest/v1/variants?select=product_id,attributes'):
        colors.setdefault(v['product_id'], set()).add(v['attributes'].get('color'))
    total = 0
    for slug, urls in mapping.items():
        pid = products.get(slug)
        if pid is None:
            print(f'  ? {slug}: no such product, skipped')
            continue
        if pid in seeded:
            print(f'  = {slug}: already has seed photos')
            continue
        rows, uploaded = [], []
        try:
            for url, color in map(entry, urls):
                if color is not None and color not in colors.get(pid, ()):
                    print(f'  ! {slug}: no variant has colour {color!r}, skipped {url[:60]}')
                    continue
                time.sleep(1)  # be polite to the brand sites
                try:
                    original = download(url)
                    try:
                        sq = squared(original)
                        full, thumb = webp(sq, 'full.webp', *FULL).read_bytes(), webp(sq, 'thumb.webp', *THUMB).read_bytes()
                    finally:
                        shutil.rmtree(original.parent, ignore_errors=True)  # brand files don't linger in /tmp
                except (OSError, ValueError, subprocess.CalledProcessError) as e:
                    print(f'  ! {slug}: {url[:80]}: {e}')
                    continue
                n, digest = len(rows) + 1, hashlib.sha256(full).hexdigest()[:10]
                for path, data in ((seed_path(pid, n, digest), full), (seed_path(pid, n, digest, True), thumb)):
                    api.upload(path, data)
                    uploaded.append(path)
                    total += len(data)
                rows.append({'product_id': pid, 'path': seed_path(pid, n, digest), 'sort': n, 'color': color})
            if rows:
                api.call('POST', '/rest/v1/product_images', rows, {'Prefer': 'return=minimal'})
        except RuntimeError:
            api.remove(uploaded)  # no orphaned files when the row insert fails
            raise
        print(f'  + {slug}: {len(rows)} of {len(urls)}')
    print(f'uploaded {total / 1024 / 1024:.1f} MB')


def remove(api: Api) -> None:
    paths = [p for prod in api.call('GET', '/rest/v1/products?select=id') for p in api.seed_objects(prod['id'])]
    api.call('DELETE', '/rest/v1/product_images?path=like.*%2Fseed-*')
    for i in range(0, len(paths), 100):
        api.remove(paths[i:i + 100])
    print(f'removed {len(paths)} seed files and their rows')


def main() -> None:
    api = Api(status())
    if sys.argv[1:] == ['--remove']:
        remove(api)
    elif not sys.argv[1:]:
        WORK.mkdir(parents=True, exist_ok=True)
        seed(api, json.loads(MAPPING.read_text()))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
