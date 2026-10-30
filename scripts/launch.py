#!/usr/bin/env python3
"""Production setup from .env.local: paste the keys there, then run

    python3 scripts/launch.py --dry-run     # shows every command; touches nothing
    python3 scripts/launch.py               # does it

Each step runs only when its keys are filled in and says what it skipped, so it is safe to run again as more
keys arrive. Steps, in order (pick some with --only schema,auth):

  link       link the Supabase CLI to the production project
  schema     apply new migrations (never the seed: production keeps its own data)
  secrets    Edge Function secrets: Razorpay, MSG91, FCM, and fresh Send SMS hook and push secrets
  functions  deploy every Edge Function
  push       phone notifications: tell the database where send-push is and its secret (Vault)
  auth       auth settings: sign-in hook, 6-digit codes, code emails, Resend SMTP, Google, MSG91 SMS hook
  cleanup    remove the test-login domain from production
  app        write app/env/prod.json, the app's build settings
  signing    create the Play upload key once, write android/key.properties, print its SHA-1 and SHA-256
  site       fill the policy pages into build/site/, with .well-known/assetlinks.json for share links
  build      release app bundle (.aab) for Play and an .apk to share

Secrets reach the CLI through environment variables or a temp file (chmod 600, deleted after), never the command
line, and nothing here prints a secret.
"""
import argparse
import base64
import json
import os
import re
import secrets as rand
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STEPS = ['link', 'schema', 'secrets', 'functions', 'push', 'auth', 'cleanup', 'app', 'signing', 'site', 'build']
TEST_DOMAIN = 'shyammobiles.test'
PACKAGE = 'com.shyammobiles.app'
KEYSTORE = ROOT / 'app/android/upload-keystore.jks'
PLACEHOLDERS = {
    '[[LEGAL BUSINESS NAME]]': 'LEGAL_BUSINESS_NAME',
    '[[GSTIN]]': 'GSTIN',
    '[[SUPPORT EMAIL]]': 'SUPPORT_EMAIL',
    '[[GRIEVANCE OFFICER NAME]]': 'GRIEVANCE_OFFICER_NAME',
    '[[DELIVERY TIME]]': 'DELIVERY_TIME',
}


def parse_env(text):
    """KEY=value lines; # comments and blank lines skipped; surrounding quotes dropped."""
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
            v = v[1:-1]
        out[k.strip()] = v
    return out


def fcm_service_account(value):
    """FCM_SERVICE_ACCOUNT as one line of JSON: the key file's JSON pasted as is, or the path to the .json file."""
    text = value if value.lstrip().startswith('{') else Path(value).expanduser().read_text()
    key = json.loads(text)
    missing = [k for k in ['project_id', 'client_email', 'private_key'] if not key.get(k)]
    if missing:
        raise ValueError(f'FCM_SERVICE_ACCOUNT has no {", ".join(missing)}: use the service account key file')
    return json.dumps(key, separators=(',', ':'))


def push_vault_sql(ref, secret):
    """SQL that stores send-push's URL and shared secret in Vault, where private.push_notification reads them."""
    if not re.fullmatch(r'[a-z0-9]{20}', ref) or not re.fullmatch(r'[A-Za-z0-9_-]{32,}', secret):
        raise ValueError('unexpected project ref or push secret')
    values = {'push_url': f'https://{ref}.supabase.co/functions/v1/send-push', 'push_secret': secret}
    return 'do $$ begin\n' + ''.join(
        f"  perform vault.update_secret(id, '{v}') from vault.secrets where name = '{k}';\n"
        f"  if not found then perform vault.create_secret('{v}', '{k}'); end if;\n" for k, v in values.items()) + 'end $$;\n'


def _set_in_section(text, section, key, value):
    """Sets `key = value` inside [section] (which must exist with that key)."""
    pattern = re.compile(rf'(^\[{re.escape(section)}\]\n(?:(?!\[).*\n)*?){re.escape(key)} = .*$', re.M)
    new, n = pattern.subn(lambda m: f'{m.group(1)}{key} = {value}', text, count=1)
    if n != 1:
        raise ValueError(f'[{section}] {key} not found in config.toml')
    return new


def prod_config(text, env, sms_hook):
    """supabase/config.toml as production needs it. The repo file is local-first: it has a test phone number with a
    fixed code, a dummy Twilio account and Google switched on with whatever is in the shell."""
    ref = env['SUPABASE_PROJECT_REF']
    # the test phone number would let anyone sign in as +91 99999 99999 with 123456
    text = re.sub(r'(^\[auth\.sms\.test_otp\]\n)(?:\d+ = "\d+"\n)+', r'\1', text, flags=re.M)
    text = _set_in_section(text, 'auth.sms.twilio', 'enabled', 'false')
    text = _set_in_section(text, 'storage.vector', 'enabled', 'false')  # as hosted projects have it
    text = re.sub(r'^site_url = .*$', f'site_url = "{env.get("POLICIES_URL") or "http://localhost:3000"}"',
                  text, count=1, flags=re.M)
    text = re.sub(r'^additional_redirect_urls = .*$', 'additional_redirect_urls = []', text, count=1, flags=re.M)
    google = bool(env.get('GOOGLE_WEB_CLIENT_ID') and env.get('GOOGLE_CLIENT_SECRET'))
    text = _set_in_section(text, 'auth.external.google', 'enabled', 'true' if google else 'false')
    extra = []
    if env.get('RESEND_API_KEY') and env.get('SMTP_SENDER_EMAIL'):
        extra.append('[auth.email.smtp]\nenabled = true\nhost = "smtp.resend.com"\nport = 465\nuser = "resend"\n'
                     'pass = "env(RESEND_API_KEY)"\nadmin_email = "env(SMTP_SENDER_EMAIL)"\n'
                     'sender_name = "Shyam Mobiles"\n')
    if sms_hook:
        extra.append(f'[auth.hook.send_sms]\nenabled = true\nuri = "https://{ref}.supabase.co/functions/v1/send-sms"\n'
                     'secrets = "env(SEND_SMS_HOOK_SECRET)"\n')
    if extra:
        text = text.rstrip('\n') + '\n\n# Added by scripts/launch.py for production\n' + '\n'.join(extra)
    return text


def fill_site(src, dst, env):
    """Copies site/ to dst with the business details filled in; returns the placeholders still empty."""
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    values = {ph: env.get(key, '') for ph, key in PLACEHOLDERS.items()}
    values['[[SMS PROVIDER]]'] = 'MSG91 (Walkover Web Solutions Pvt Ltd)'
    left = set()
    for page in dst.glob('*.html'):
        html = page.read_text()
        for ph, value in values.items():
            if value:
                html = html.replace(ph, value)
        left |= set(re.findall(r'\[\[[A-Z ]+\]\]', html))
        page.write_text(html)
    return sorted(left)


def key_fingerprints(keytool_out):
    """(SHA-1, SHA-256) from `keytool -list -v`; None where missing."""
    def find(name):
        m = re.search(rf'{name}: ([0-9A-F:]+)', keytool_out or '')
        return m.group(1) if m else None
    return find('SHA1'), find('SHA256')


SHA256 = re.compile(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')


def assetlinks(fingerprints):
    """build/site/.well-known/assetlinks.json: lets Android open https://<LINK_HOST>/open links in the app. Every key
    that signs a copy people install: the upload key (sideloaded .apk) and Play's app-signing key (Play installs)."""
    return json.dumps([{
        'relation': ['delegate_permission/common.handle_all_urls'],
        'target': {'namespace': 'android_app', 'package_name': PACKAGE, 'sha256_cert_fingerprints': fingerprints},
    }], indent=2) + '\n'


class Launch:
    def __init__(self, env, dry):
        self.env, self.dry = env, dry
        self.cli = os.environ.get('SUPABASE_CLI') or shutil.which('supabase-go') or 'supabase'
        self.hook_secret = None
        self.push_secret = None
        self.upload_sha256 = None
        self.skipped = []

    def has(self, *keys):
        return all(self.env.get(k) for k in keys)

    def skip(self, step, why):
        self.skipped.append(f'{step}: {why}')
        print(f'  skipped: {why}')

    def run(self, cmd, cwd=ROOT, env=None):
        print('  $ ' + ' '.join(str(c) for c in cmd))
        if self.dry:
            return ''
        done = subprocess.run([str(c) for c in cmd], cwd=cwd, env={**os.environ, **(env or {})}, check=True,
                              stdout=subprocess.PIPE, text=True)
        return done.stdout

    @property
    def db_env(self):
        return {'SUPABASE_DB_PASSWORD': self.env['SUPABASE_DB_PASSWORD']}

    @property
    def msg91(self):
        return self.has('MSG91_AUTH_KEY', 'MSG91_TEMPLATE_ID')

    # steps ---------------------------------------------------------------------------------------------------------

    def link(self):
        self.run([self.cli, 'link', '--project-ref', self.env['SUPABASE_PROJECT_REF']], env=self.db_env)

    def schema(self):
        self.run([self.cli, 'db', 'push', '--linked', '--yes'], env=self.db_env)

    def secrets(self):
        values = {}
        razorpay = ['RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET', 'RAZORPAY_WEBHOOK_SECRET']
        if self.has(*razorpay):
            values.update({k: self.env[k] for k in razorpay})
            if self.env['RAZORPAY_KEY_ID'].startswith('rzp_test_'):
                print('  note: Razorpay test keys, so payments are pretend. Swap in rzp_live_ keys to take money.')
        else:
            self.skip('secrets', 'Razorpay needs all three of RAZORPAY_KEY_ID, _KEY_SECRET, _WEBHOOK_SECRET')
        if self.msg91:
            # a new secret every run; the auth step hands the same one to Auth in this run
            self.hook_secret = 'v1,whsec_' + base64.b64encode(rand.token_bytes(32)).decode()
            values.update(MSG91_AUTH_KEY=self.env['MSG91_AUTH_KEY'], MSG91_TEMPLATE_ID=self.env['MSG91_TEMPLATE_ID'],
                          SEND_SMS_HOOK_SECRET=self.hook_secret)
        else:
            self.skip('secrets', 'phone codes need MSG91_AUTH_KEY and MSG91_TEMPLATE_ID')
        if self.has('FCM_SERVICE_ACCOUNT'):
            # a new secret every run; the push step hands the same one to the database in this run
            self.push_secret = rand.token_urlsafe(32)
            values.update(FCM_SERVICE_ACCOUNT=fcm_service_account(self.env['FCM_SERVICE_ACCOUNT']),
                          PUSH_SECRET=self.push_secret)
        else:
            self.skip('secrets', 'phone notifications stay off until FCM_SERVICE_ACCOUNT is in')
        if not values:
            return
        print(f'  (setting {", ".join(values)})')
        if self.dry:
            return print(f'  $ {self.cli} secrets set --env-file <temp file> --project-ref {self.env["SUPABASE_PROJECT_REF"]}')
        fd, path = tempfile.mkstemp(suffix='.env')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(''.join(f'{k}={v}\n' for k, v in values.items()))
            self.run([self.cli, 'secrets', 'set', '--env-file', path, '--project-ref', self.env['SUPABASE_PROJECT_REF']])
        finally:
            os.unlink(path)

    def functions(self):
        self.run([self.cli, 'functions', 'deploy', '--use-api', '--project-ref', self.env['SUPABASE_PROJECT_REF']])

    def push(self):
        if self.push_secret is None:
            return self.skip('push', 'phone notifications need FCM_SERVICE_ACCOUNT (and the secrets step in the same run)')
        if not self.has('FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID'):
            self.skip('push', 'the app build needs the FIREBASE_* keys too, or phones never register for notifications')
        sql = push_vault_sql(self.env['SUPABASE_PROJECT_REF'], self.push_secret)
        if self.dry:
            return print(f'  $ {self.cli} db query --linked -f <temp file: Vault push_url, push_secret>')
        fd, path = tempfile.mkstemp(suffix='.sql')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(sql)
            self.run([self.cli, 'db', 'query', '--linked', '--agent', 'no', '-f', path], env=self.db_env)
        finally:
            os.unlink(path)

    def auth(self):
        if not self.has('RESEND_API_KEY', 'SMTP_SENDER_EMAIL'):
            self.skip('auth', 'no Resend key yet: Supabase’s own mailer sends only a few sign-in emails an hour')
        if not self.has('GOOGLE_WEB_CLIENT_ID', 'GOOGLE_CLIENT_SECRET'):
            self.skip('auth', 'Google sign-in stays off until GOOGLE_WEB_CLIENT_ID and GOOGLE_CLIENT_SECRET are in')
        sms_hook = self.msg91 and (self.hook_secret is not None or self.dry)
        if not self.msg91:
            self.skip('auth', 'phone sign-in has no SMS sender until MSG91 keys are in')
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / 'supabase'
            shutil.copytree(ROOT / 'supabase/templates', work / 'templates')
            if (ROOT / 'supabase/.temp').exists():
                shutil.copytree(ROOT / 'supabase/.temp', work / '.temp')
            (work / 'config.toml').write_text(prod_config((ROOT / 'supabase/config.toml').read_text(), self.env, sms_hook))
            env = {k: self.env.get(k, '') for k in
                   ['GOOGLE_WEB_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'RESEND_API_KEY', 'SMTP_SENDER_EMAIL']}
            env.update(SEND_SMS_HOOK_SECRET=self.hook_secret or '', SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN='unused')
            self.run([self.cli, 'config', 'push', '--workdir', tmp, '--yes'], env=env)

    def cleanup(self):
        self.run([self.cli, 'db', 'query', '--linked', '--agent', 'no',
                  f"delete from private.password_sign_in_domains where domain = '{TEST_DOMAIN}'"], env=self.db_env)

    def app(self):
        keys = ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'RAZORPAY_KEY_ID', 'GOOGLE_WEB_CLIENT_ID', 'POLICIES_URL',
                'LINK_HOST', 'FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID']
        values = {k: self.env.get(k, '') for k in keys}
        path = ROOT / 'app/env/prod.json'
        print(f'  writing {path.relative_to(ROOT)} ({", ".join(k for k in keys if values[k])})')
        for k in ['RAZORPAY_KEY_ID', 'GOOGLE_WEB_CLIENT_ID', 'POLICIES_URL', 'LINK_HOST', 'FIREBASE_APP_ID']:
            if not values[k]:
                self.skip('app', f'{k} is empty, so that part of the app stays off in this build')
        if self.dry:
            return
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(values, f, indent=2)

    def signing(self):
        if not self.has('ANDROID_KEYSTORE_PASSWORD'):
            return self.skip('signing', 'ANDROID_KEYSTORE_PASSWORD is empty')
        if len(self.env['ANDROID_KEYSTORE_PASSWORD']) < 12:
            return self.skip('signing', 'use a password of at least 12 characters')
        alias = self.env.get('ANDROID_KEY_ALIAS') or 'upload'
        pw = {'ANDROID_KEYSTORE_PASSWORD': self.env['ANDROID_KEYSTORE_PASSWORD']}
        if KEYSTORE.exists():
            print(f'  {KEYSTORE.relative_to(ROOT)} already exists: keeping it (a new one could never update the app)')
        else:
            org = self.env.get('LEGAL_BUSINESS_NAME') or 'Shyam Mobiles'
            self.run(['keytool', '-genkeypair', '-keystore', KEYSTORE, '-alias', alias, '-keyalg', 'RSA',
                      '-keysize', '4096', '-validity', '10000', '-storetype', 'PKCS12',
                      '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD',
                      '-dname', f'CN=Shyam Mobiles, O={org}, L=Waidhan, ST=Madhya Pradesh, C=IN'], env=pw)
        if not self.dry:
            props = ROOT / 'app/android/key.properties'
            fd = os.open(props, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            password = self.env['ANDROID_KEYSTORE_PASSWORD']
            # PKCS12 keeps one password for the store and the key
            with os.fdopen(fd, 'w') as f:
                f.write(f'storeFile=../upload-keystore.jks\nstorePassword={password}\nkeyAlias={alias}\n'
                        f'keyPassword={password}\n')
        sha1, self.upload_sha256 = self.upload_fingerprints()
        if sha1:
            print(f'  upload key SHA-1: {sha1}  (Google Cloud > Android OAuth client; add Play’s app '
                  'signing SHA-1 too, from Play Console > Setup > App signing)')
        if self.upload_sha256:
            print(f'  upload key SHA-256: {self.upload_sha256}  (share links: the site step puts it in assetlinks.json)')
        print('  back up app/android/upload-keystore.jks and its password: without them the app can’t be updated')

    def upload_fingerprints(self):
        """(SHA-1, SHA-256) of the upload key, when it exists and its password is in."""
        if not ((KEYSTORE.exists() or self.dry) and self.has('ANDROID_KEYSTORE_PASSWORD')):
            return None, None
        out = self.run(['keytool', '-list', '-v', '-keystore', KEYSTORE, '-alias',
                        self.env.get('ANDROID_KEY_ALIAS') or 'upload', '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD'],
                       env={'ANDROID_KEYSTORE_PASSWORD': self.env['ANDROID_KEYSTORE_PASSWORD']})
        return key_fingerprints(out)

    def site(self):
        print('  writing build/site/')
        play = self.env.get('PLAY_SIGNING_SHA256', '').strip().upper()
        if play and not SHA256.match(play):
            self.skip('site', 'PLAY_SIGNING_SHA256 should look like AB:CD:… (32 pairs), from Play Console > App signing')
            play = ''
        if self.upload_sha256 is None:
            self.upload_sha256 = self.upload_fingerprints()[1]
        keys = [k for k in [self.upload_sha256, play] if k]
        if not keys and not self.dry:
            self.skip('site', 'share links open the browser, not the app, until assetlinks.json has a key: '
                              'the upload key (step signing) or PLAY_SIGNING_SHA256')
        if not play:
            self.skip('site', 'PLAY_SIGNING_SHA256 is empty, so share links won’t open copies installed from Play')
        if self.dry:
            return
        left = fill_site(ROOT / 'site', ROOT / 'build/site', self.env)
        if keys:
            (ROOT / 'build/site/.well-known').mkdir()
            (ROOT / 'build/site/.well-known/assetlinks.json').write_text(assetlinks(keys))
            print(f'  wrote .well-known/assetlinks.json ({len(keys)} key{"s" if len(keys) > 1 else ""})')
        if left:
            self.skip('site', f'still blank: {", ".join(left)}')
        else:
            print('  build/site/ is complete: publish it (with .well-known/) at LINK_HOST, put its address in '
                  'POLICIES_URL and run --only app,auth')

    def build(self):
        if not (ROOT / 'app/android/key.properties').exists() and not self.dry:
            return self.skip('build', 'no signing key yet (step signing)')
        defines = '--dart-define-from-file=env/prod.json'
        self.run(['flutter', 'build', 'appbundle', '--release', defines], cwd=ROOT / 'app')
        self.run(['flutter', 'build', 'apk', '--release', '--target-platform', 'android-arm64', defines], cwd=ROOT / 'app')
        print('  Play: app/build/app/outputs/bundle/release/app-release.aab\n'
              '  share: app/build/app/outputs/flutter-apk/app-release.apk')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--dry-run', action='store_true', help='print the commands; change nothing')
    p.add_argument('--only', help='comma-separated steps: ' + ','.join(STEPS))
    p.add_argument('--env', default=str(ROOT / '.env.local'), help='key file (default .env.local)')
    a = p.parse_args()
    env = parse_env(Path(a.env).read_text())
    steps = STEPS if not a.only else [s.strip() for s in a.only.split(',')]
    unknown = [s for s in steps if s not in STEPS]
    if unknown:
        sys.exit(f'unknown steps: {", ".join(unknown)}')
    if 'auth' in steps and 'secrets' not in steps and env.get('MSG91_AUTH_KEY'):
        steps.insert(steps.index('auth'), 'secrets')  # the SMS hook secret must reach the function and Auth together
    if 'push' in steps and 'secrets' not in steps and env.get('FCM_SERVICE_ACCOUNT'):
        steps.insert(steps.index('push'), 'secrets')  # the push secret must reach send-push and the database together
    missing = [k for k in ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_PROJECT_REF', 'SUPABASE_DB_PASSWORD']
               if not env.get(k)]
    if missing:
        sys.exit(f'{a.env} is missing {", ".join(missing)}')
    if f'//{env["SUPABASE_PROJECT_REF"]}.supabase.co' not in env['SUPABASE_URL']:
        sys.exit('SUPABASE_URL and SUPABASE_PROJECT_REF point at different projects')
    launch = Launch(env, a.dry_run)
    for step in [s for s in STEPS if s in steps]:
        print(f'\n== {step}')
        try:
            getattr(launch, step)()
        except subprocess.CalledProcessError as e:
            sys.exit(f'\n{step} failed (exit {e.returncode}). Fix it and run again with --only {step}.')
    print('\nDone.' + ('' if not launch.skipped else ' Still waiting on:\n  - ' + '\n  - '.join(launch.skipped)))


if __name__ == '__main__':
    main()
