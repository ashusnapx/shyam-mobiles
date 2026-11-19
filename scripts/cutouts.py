#!/usr/bin/env python3
"""Cut-outs for the LOCAL stack's photos: every product and banner photo <key>.webp gets <key minus ext>@cut.webp
beside it (supabase.dart cutPathFor), the subject alone on a transparent background (rembg), trimmed to its edges,
at most 1200 px, WebP with alpha. Photos that already have one are skipped. scripts/demo_deploy.py copies them to
production with the photos; new admin uploads make their own on the phone (ML Kit, admin/data/photos.dart).

Local stack only (seed_photos.local_api refuses anything but 127.0.0.1). Never prints a key. rembg is not a repo
dependency: run it from a throwaway venv outside the repo, e.g.
    python3.13 -m venv "$TMPDIR/cutouts" && "$TMPDIR/cutouts/bin/pip" install 'rembg[cpu]' pillow  # 3.13: has wheels
    "$TMPDIR/cutouts/bin/python" scripts/cutouts.py
Its model downloads to ~/.u2net, outside the repo too.
"""
import io
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dev_setup import status  # noqa: E402
from seed_photos import BUCKET, Api  # noqa: E402

MAX_SIDE = 1200
MODEL = 'isnet-general-use'  # ~170 MB, clean product edges; rembg's newer default is a 1 GB model, too big for 8 GB
_session = None


def cut_path(path: str) -> str:
    """p1/1730000000000.webp -> p1/1730000000000@cut.webp (any extension), as the app's cutPathFor."""
    return path.rsplit('.', 1)[0] + '@cut.webp' if '.' in path.rsplit('/', 1)[-1] else path + '@cut.webp'


def cutout(data: bytes) -> bytes:
    from PIL import Image
    from rembg import new_session, remove

    global _session
    _session = _session or new_session(MODEL)
    img = remove(Image.open(io.BytesIO(data)).convert('RGBA'), session=_session)
    box = img.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()  # trim the empty margins
    if box:
        img = img.crop(box)
    img.thumbnail((MAX_SIDE, MAX_SIDE))
    out = io.BytesIO()
    img.save(out, 'WEBP', quality=85, method=6)  # RGBA: the alpha is kept
    return out.getvalue()


def exists(api: Api, path: str) -> bool:
    try:
        with urllib.request.urlopen(urllib.request.Request(f'{api.base}/storage/v1/object/public/{BUCKET}/{path}', method='HEAD'), timeout=15):
            return True
    except urllib.error.HTTPError:
        return False


def main() -> None:
    api = Api(status())
    rows = (api.call('GET', '/rest/v1/product_images?select=path') or []) + \
        (api.call('GET', '/rest/v1/banners?select=path:image_path&image_path=not.is.null') or [])
    todo = sorted({r['path'] for r in rows} - {None})
    made = skipped = failed = 0
    for path in todo:
        if exists(api, cut_path(path)):
            skipped += 1
            continue
        try:
            with urllib.request.urlopen(f'{api.base}/storage/v1/object/public/{BUCKET}/{path}', timeout=30) as r:
                api.upload(cut_path(path), cutout(r.read()))
            made += 1
            print(f'  {made} {cut_path(path)}')
        except Exception as e:  # one bad photo shouldn't stop the rest; the app falls back to the photo
            failed += 1
            print(f'  skipped {path}: {e}')
    print(f'{made} cut-outs made, {skipped} already there, {failed} failed')


if __name__ == '__main__':
    main()
