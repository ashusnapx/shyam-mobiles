#!/usr/bin/env python3
"""Put the full app on the production Supabase project for a client demo, and build the demo APK.

    python3 scripts/demo_deploy.py            # everything below, then ~/Downloads/ShyamMobiles-demo.apk
    python3 scripts/demo_deploy.py --no-build # backend only
    python3 scripts/demo_deploy.py --remove-demo   # before launch: delete the demo accounts and the brand photos

Steps: link, apply new migrations, add the sample catalogue and offers (conflict-safe), set the Edge Function
secrets (Razorpay TEST keys, the FCM key, a push secret), deploy every function, point the database's push trigger
at send-push, create a demo customer and a demo admin, copy the brand photos from the local stack, and build a release
APK with the demo login buttons (DEMO_BUILD=true).

Reads local.env (production URL, keys, DB password), the Razorpay test env file and the Firebase service-account key
already on this Mac. Prints no secrets. Safe to run again. Demo passwords live in ~/.config/shyam-mobiles (600).
The demo admin password ends up inside the APK: share it only with the client, and run --remove-demo after the demo.
"""
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONF = Path.home() / '.config/shyam-mobiles'
SA_FILE = CONF / 'fcm-service-account.json'
DEMO_FILE = CONF / 'demo-accounts.json'
RAZORPAY_ENV = Path('/private/tmp/claude-501/-Users-ashutoshkumar-shyam-mobiles/1cff526c-8d97-4431-b1cc-9a16bbbdcebc'
                    '/scratchpad/razorpay-test.env')
LOCAL_API = 'http://127.0.0.1:54321'
CLI = shutil.which('supabase-go') or 'supabase'
DEMO = {'customer': ('demo.customer@shyammobiles.test', 'Demo Customer'),
        'admin': ('demo.admin@shyammobiles.test', 'Demo Admin (staff)')}


def parse_env(path):
    out = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def step(title):
    print(f'\n== {title}', flush=True)


def run(cmd, env=None, input=None):
    done = subprocess.run([str(c) for c in cmd], cwd=ROOT, env={**os.environ, **(env or {})}, input=input,
                          capture_output=True, text=True)
    if done.returncode:
        sys.exit(f'failed: {" ".join(str(c) for c in cmd[:3])}…\n{(done.stderr or done.stdout)[-800:]}')
    return done.stdout


def private_write(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write(text)


def http(method, url, key, body=None, headers=None):
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    h = {'apikey': key, 'Authorization': f'Bearer {key}', **(headers or {})}
    if body is not None and not isinstance(body, bytes):
        h.setdefault('Content-Type', 'application/json')
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw and r.headers.get('Content-Type', '').startswith('application/json') else raw
    except urllib.error.HTTPError as e:
        return {'_error': e.code, '_body': e.read().decode()[:300]}


class Deploy:
    def __init__(self):
        self.env = parse_env(ROOT / 'local.env')
        self.ref = self.env['SUPABASE_PROJECT_REF']
        self.url = self.env['SUPABASE_URL'].rstrip('/')
        assert f'//{self.ref}.supabase.co' in self.url, 'local.env URL and project ref disagree'
        self.db_env = {'SUPABASE_DB_PASSWORD': self.env['SUPABASE_DB_PASSWORD']}
        CONF.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.state = json.loads(DEMO_FILE.read_text()) if DEMO_FILE.exists() else {}
        for role in DEMO:
            self.state.setdefault(f'{role}_password', secrets.token_urlsafe(18))
        self.state.setdefault('push_secret', secrets.token_urlsafe(32))
        private_write(DEMO_FILE, json.dumps(self.state, indent=2))
        self._secret = None

    @property
    def secret_key(self):
        if self._secret is None:
            keys = json.loads(run([CLI, 'projects', 'api-keys', '--project-ref', self.ref, '-o', 'json']))
            pick = [k for k in keys if str(k.get('api_key', '')).startswith('sb_secret_')] or \
                   [k for k in keys if k.get('name') == 'service_role']
            if not pick:
                sys.exit('no secret or service_role key found for the project')
            self._secret = pick[0]['api_key']
        return self._secret

    def query(self, sql):
        fd, path = tempfile.mkstemp(suffix='.sql')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(sql)
            return run([CLI, 'db', 'query', '--linked', '--agent', 'no', '-f', path], env=self.db_env)
        finally:
            os.unlink(path)

    def link(self):
        step('link the production project')
        run([CLI, 'link', '--project-ref', self.ref], env=self.db_env)

    def migrations(self):
        step('apply new migrations')
        out = run([CLI, 'db', 'push', '--linked', '--yes'], env=self.db_env)
        print('  ' + ('applied' if 'Applying' in out or 'Finished' in out else 'up to date'))

    def catalogue(self):
        step('sample catalogue, offers and banners (conflict-safe)')
        seed = (ROOT / 'supabase/seed.sql').read_text()
        products = seed[seed.index('-- More products in every category'):seed.index('-- The shop: ')]
        offers = seed[seed.index('-- Offers (docs/SPEC.md'):]
        fixes = ("update public.variants set sku = 'AN-NANO20-BLK', name = 'Black', "
                 "attributes = '{\"color\":\"Black\",\"color_hex\":\"#1F1F1F\"}' where sku = 'AN-NANO20-WHT';\n"
                 "update public.variants set sku = 'SAM-EBP10-BEG', name = 'Beige', "
                 "attributes = '{\"color\":\"Beige\",\"color_hex\":\"#D9CBB3\"}' where sku = 'SAM-EBP10-GRY';\n"
                 # products dropped from the sample catalogue because no official photos exist
                 "delete from public.products where slug in ('ambrane-stylo-pro-10000mah', 'itel-magic-x-play', "
                 "'jio-bharat-b1-4g', 'portronics-konnect-l-type-c-to-lightning', 'realme-narzo-80-pro-5g', "
                 "'spigen-glastr-slim-pixel-9a', 'spigen-neo-flex-oneplus-13');\n")
        self.query(products + '\n' + offers + '\n' + fixes)
        print('  done')

    def secrets(self):
        step('Edge Function secrets (Razorpay TEST keys, FCM, push secret)')
        rz = parse_env(RAZORPAY_ENV)
        assert rz['RAZORPAY_KEY_ID'].startswith('rzp_test_'), 'only test keys for the demo'
        sa = json.dumps(json.loads(SA_FILE.read_text()), separators=(',', ':'))
        fd, path = tempfile.mkstemp(suffix='.env')
        os.close(fd)
        try:
            private_write(path, ''.join(f'{k}={rz[k]}\n' for k in ['RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET',
                                                                     'RAZORPAY_WEBHOOK_SECRET'])
                          + f"FCM_SERVICE_ACCOUNT='{sa}'\nPUSH_SECRET={self.state['push_secret']}\n")
            run([CLI, 'secrets', 'set', '--env-file', path, '--project-ref', self.ref])
        finally:
            os.unlink(path)
        print('  set: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET, FCM_SERVICE_ACCOUNT, PUSH_SECRET')

    def functions(self):
        step('deploy every Edge Function')
        run([CLI, 'functions', 'deploy', '--use-api', '--project-ref', self.ref])
        print('  deployed')

    def push(self):
        step('point the push trigger at send-push')
        values = {'push_url': f'{self.url}/functions/v1/send-push', 'push_secret': self.state['push_secret']}
        self.query('do $$ begin\n' + ''.join(
            f"  perform vault.update_secret(id, '{v}') from vault.secrets where name = '{k}';\n"
            f"  if not found then perform vault.create_secret('{v}', '{k}'); end if;\n" for k, v in values.items())
            + 'end $$;\n')
        print('  done')

    def accounts(self):
        step('demo customer and demo admin')
        key = self.secret_key
        users = http('GET', f'{self.url}/auth/v1/admin/users?per_page=1000', key)
        by_email = {u['email']: u['id'] for u in (users.get('users', []) if isinstance(users, dict) else [])}
        for role, (email, name) in DEMO.items():
            password = self.state[f'{role}_password']
            if email in by_email:
                uid = by_email[email]
                r = http('PUT', f'{self.url}/auth/v1/admin/users/{uid}', key, {'password': password, 'email_confirm': True})
            else:
                r = http('POST', f'{self.url}/auth/v1/admin/users', key,
                         {'email': email, 'password': password, 'email_confirm': True, 'user_metadata': {'full_name': name}})
                uid = r.get('id') if isinstance(r, dict) else None
            if not uid or (isinstance(r, dict) and r.get('_error')):
                sys.exit(f'could not set up {email}: {r}')
            http('PATCH', f'{self.url}/rest/v1/profiles?id=eq.{uid}', key, {'full_name': name})
            if role == 'admin':
                http('POST', f'{self.url}/rest/v1/admins', key, {'user_id': uid},
                     {'Prefer': 'resolution=ignore-duplicates'})
            print(f'  {role}: {email}')

    def photos(self):
        step('brand photos from the local stack (replace with the shop\'s own before launch)')
        key = self.secret_key
        local = subprocess.run(['psql', 'postgresql://postgres:postgres@127.0.0.1:54322/postgres', '-At', '-F', '\t', '-c',
                                "select p.slug, pi.path, pi.sort, coalesce(pi.color, '') from public.product_images pi "
                                "join public.products p on p.id = pi.product_id where pi.path like '%/seed-%'"],
                               capture_output=True, text=True)
        if local.returncode:
            print('  skipped: the local stack is not running')
            return
        rows = [line.split('\t') for line in local.stdout.splitlines() if line]
        prod = {p['slug']: p['id'] for p in http('GET', f'{self.url}/rest/v1/products?select=id,slug', key)}
        have = {r['path'] for r in http('GET', f'{self.url}/rest/v1/product_images?select=path', key)}
        copied = 0
        for slug, path, sort, color in rows:
            pid = prod.get(slug)
            if not pid:
                continue
            name = path.split('/', 1)[1]
            new = f'{pid}/{name}'
            if new in have:
                continue
            for p_local, p_new in [(path, new), (path.replace('.webp', '@thumb.webp'), new.replace('.webp', '@thumb.webp'))]:
                with urllib.request.urlopen(f'{LOCAL_API}/storage/v1/object/public/product-images/{p_local}', timeout=30) as r:
                    data = r.read()
                http('POST', f'{self.url}/storage/v1/object/product-images/{p_new}', key, data,
                     {'Content-Type': 'image/webp', 'cache-control': 'max-age=31536000', 'x-upsert': 'true'})
            http('POST', f'{self.url}/rest/v1/product_images', key,
                 {'product_id': pid, 'path': new, 'sort': int(sort), 'color': color or None})
            copied += 1
        print(f'  {copied} photos copied')

    def build(self):
        step('demo APK (release, arm64, demo logins on)')
        rz = parse_env(RAZORPAY_ENV)
        dev = json.loads((ROOT / 'app/env/dev.json').read_text())
        demo = {
            'SUPABASE_URL': self.url,
            'SUPABASE_PUBLISHABLE_KEY': self.env['SUPABASE_PUBLISHABLE_KEY'],
            'RAZORPAY_KEY_ID': rz['RAZORPAY_KEY_ID'],
            'POLICIES_URL': '',
            'LINK_HOST': 'shyammobiles.example',
            'DEV_LOGIN': 'true',
            'DEMO_BUILD': 'true',
            'DEV_CUSTOMER_EMAIL': DEMO['customer'][0],
            'DEV_CUSTOMER_PASSWORD': self.state['customer_password'],
            'DEV_ADMIN_EMAIL': DEMO['admin'][0],
            'DEV_ADMIN_PASSWORD': self.state['admin_password'],
            **{k: dev[k] for k in ['FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID',
                                    'FIREBASE_PROJECT_ID'] if dev.get(k)},
        }
        private_write(ROOT / 'app/env/demo.json', json.dumps(demo, indent=2))
        subprocess.run(['flutter', 'build', 'apk', '--release', '--target-platform', 'android-arm64', '--obfuscate',
                        '--split-debug-info=build/symbols', '--dart-define-from-file=env/demo.json'],
                       cwd=ROOT / 'app', check=True)
        out = Path.home() / 'Downloads/ShyamMobiles-demo.apk'
        shutil.copyfile(ROOT / 'app/build/app/outputs/flutter-apk/app-release.apk', out)
        print(f'  saved {out} ({out.stat().st_size / 1e6:.1f} MB)')

    def check(self):
        step('check: the demo customer can sign in and see the catalogue')
        r = http('POST', f'{self.url}/auth/v1/token?grant_type=password', self.env['SUPABASE_PUBLISHABLE_KEY'],
                 {'email': DEMO['customer'][0], 'password': self.state['customer_password']})
        token = r.get('access_token') if isinstance(r, dict) else None
        print('  sign-in:', 'ok' if token else f'FAILED {r}')
        if token:
            req = urllib.request.Request(f'{self.url}/rest/v1/product_cards?select=id',
                                         headers={'apikey': self.env['SUPABASE_PUBLISHABLE_KEY'],
                                                  'Authorization': f'Bearer {token}'})
            with urllib.request.urlopen(req, timeout=30) as resp:
                print('  products:', len(json.loads(resp.read())))

    def remove_demo(self):
        step('remove the demo accounts and the brand photos')
        key = self.secret_key
        users = http('GET', f'{self.url}/auth/v1/admin/users?per_page=1000', key)
        for u in users.get('users', []) if isinstance(users, dict) else []:
            if u['email'] in {e for e, _ in DEMO.values()}:
                http('DELETE', f'{self.url}/auth/v1/admin/users/{u["id"]}', key)
                print('  deleted', u['email'])
        rows = http('GET', f'{self.url}/rest/v1/product_images?select=path&path=like.*%2Fseed-*', key)
        paths = [p for r in rows for p in (r['path'], r['path'].replace('.webp', '@thumb.webp'))]
        if paths:
            http('DELETE', f'{self.url}/storage/v1/object/product-images', key, {'prefixes': paths})
            http('DELETE', f'{self.url}/rest/v1/product_images?path=like.*%2Fseed-*', key)
        print(f'  removed {len(rows)} brand photos')


def main():
    d = Deploy()
    if '--remove-demo' in sys.argv:
        d.link()
        return d.remove_demo()
    for s in ['link', 'migrations', 'catalogue', 'secrets', 'functions', 'push', 'accounts', 'photos', 'check']:
        getattr(d, s)()
    if '--no-build' not in sys.argv:
        d.build()
    print('\nDone. Share ~/Downloads/ShyamMobiles-demo.apk only with the client; run with --remove-demo afterwards.')


if __name__ == '__main__':
    main()
