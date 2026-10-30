#!/usr/bin/env python3
"""Local dev setup: two test accounts on the local Supabase stack and app/env/dev.json for on-device builds.

  python3 scripts/dev_setup.py        # after `supabase-go start` (or any `db reset`, which wipes auth users)

Creates or refreshes customer@shyammobiles.test and admin@shyammobiles.test (admin is added to `admins`),
writes app/env/dev.json (gitignored) with the local URL, publishable key and the accounts' passwords, and
never prints a key or password. Local stack only: it refuses any API URL that isn't 127.0.0.1/localhost.
"""
import json
import secrets
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEV_JSON = ROOT / 'app' / 'env' / 'dev.json'
USERS = {
    'CUSTOMER': ('customer@shyammobiles.test', 'Rahul Kumar', '+919876543210', False),
    'ADMIN': ('admin@shyammobiles.test', 'Shyam (staff)', None, True),
}


def status() -> dict:
    out = subprocess.run(['supabase-go', 'status', '-o', 'env'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return {k: v.strip('"') for k, _, v in (line.partition('=') for line in out.splitlines()) if v}


def admin_api(env: dict, method: str, path: str, body: dict | None = None) -> dict:
    key = env['SERVICE_ROLE_KEY']
    req = urllib.request.Request(
        f"{env['API_URL']}/auth/v1/admin/{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'apikey': key, 'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read() or b'{}')


def psql(env: dict, sql: str, *params: str) -> None:
    args = ['psql', env['DB_URL'], '-v', 'ON_ERROR_STOP=1', '-q']
    for i, p in enumerate(params):
        args += ['-v', f'p{i}={p}']
    # :'p0' interpolation only happens for SQL read from input, not for -c
    subprocess.run(args, input=sql, text=True, check=True, capture_output=True)


def main() -> None:
    env = status()
    assert env['API_URL'].startswith(('http://127.0.0.1', 'http://localhost')), 'refusing: not the local stack'
    existing = {u['email']: u['id'] for u in admin_api(env, 'GET', 'users?per_page=1000').get('users', [])}
    # Reuse passwords already baked into an installed dev APK; only new setups get fresh ones.
    previous = json.loads(DEV_JSON.read_text()) if DEV_JSON.exists() else {}
    out = {
        # The phone reaches this Mac's stack through `adb reverse tcp:54321 tcp:54321`.
        'SUPABASE_URL': 'http://127.0.0.1:54321',
        'SUPABASE_PUBLISHABLE_KEY': env.get('PUBLISHABLE_KEY') or env['ANON_KEY'],
        'RAZORPAY_KEY_ID': '',
        'GOOGLE_WEB_CLIENT_ID': '',
        'GOOGLE_IOS_CLIENT_ID': '',
        'POLICIES_URL': '',  # set once site/ is published
        # .example is reserved (RFC 2606): share links look real in testing but can never open a stranger's site
        'LINK_HOST': 'shyammobiles.example',
        'DEV_LOGIN': 'true',
    }
    for role, (email, name, phone, is_admin) in USERS.items():
        password = previous.get(f'DEV_{role}_PASSWORD') or secrets.token_urlsafe(18)
        body = {'email': email, 'password': password, 'email_confirm': True}
        uid = admin_api(env, 'PUT', f'users/{existing[email]}', body)['id'] if email in existing \
            else admin_api(env, 'POST', 'users', body)['id']
        psql(env, "update public.profiles set full_name = :'p1', phone = nullif(:'p2', '') where id = :'p0'",
             uid, name, phone or '')
        if is_admin:
            psql(env, "insert into public.admins (user_id) values (:'p0') on conflict do nothing", uid)
        out[f'DEV_{role}_EMAIL'] = email
        out[f'DEV_{role}_PASSWORD'] = password
        print(f'{role.lower():8} {email}  ready{" (staff)" if is_admin else ""}')
    DEV_JSON.write_text(json.dumps(out, indent=2) + '\n')
    DEV_JSON.chmod(0o600)
    print(f'wrote {DEV_JSON.relative_to(ROOT)} (gitignored)')


if __name__ == '__main__':
    try:
        main()
    except urllib.error.HTTPError as e:
        raise SystemExit(f'auth admin API error {e.code}: {e.read().decode()[:200]}')
