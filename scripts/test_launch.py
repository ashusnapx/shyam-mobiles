"""python3 -m unittest scripts/test_launch.py — checks the production config and policy pages launch.py writes."""
import json
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from launch import (ROOT, SHA256, Launch, assetlinks, fcm_service_account, fill_site, key_fingerprints,  # noqa: E402
                    parse_env, prod_config, push_vault_sql)

CONFIG = (ROOT / 'supabase/config.toml').read_text()
BASE = {'SUPABASE_PROJECT_REF': 'abcdefghijklmnopqrst'}


class ProdConfig(unittest.TestCase):
    def load(self, env, sms_hook=False):
        return tomllib.loads(prod_config(CONFIG, {**BASE, **env}, sms_hook))

    def test_local_only_settings_never_reach_production(self):
        c = self.load({})
        self.assertEqual(c['auth']['sms']['test_otp'], {})  # no fixed code for a test number
        self.assertFalse(c['auth']['sms']['twilio']['enabled'])
        self.assertFalse(c['auth']['external']['google']['enabled'])
        self.assertFalse(c['storage']['vector']['enabled'])
        self.assertEqual(c['auth']['additional_redirect_urls'], [])
        self.assertNotIn('smtp', c['auth']['email'])
        self.assertNotIn('send_sms', c['auth']['hook'])
        self.assertTrue(c['auth']['hook']['custom_access_token']['enabled'])  # the password-grant block stays
        self.assertEqual(c['auth']['email']['otp_length'], 6)

    def test_keys_switch_on_their_parts(self):
        c = self.load({'GOOGLE_WEB_CLIENT_ID': 'x', 'GOOGLE_CLIENT_SECRET': 'y', 'RESEND_API_KEY': 're_1',
                       'SMTP_SENDER_EMAIL': 'no-reply@shop.in', 'POLICIES_URL': 'https://shop.in'}, sms_hook=True)
        self.assertTrue(c['auth']['external']['google']['enabled'])
        smtp = c['auth']['email']['smtp']
        self.assertEqual((smtp['host'], smtp['port'], smtp['pass']), ('smtp.resend.com', 465, 'env(RESEND_API_KEY)'))
        hook = c['auth']['hook']['send_sms']
        self.assertEqual(hook['uri'], 'https://abcdefghijklmnopqrst.supabase.co/functions/v1/send-sms')
        self.assertEqual(hook['secrets'], 'env(SEND_SMS_HOOK_SECRET)')
        self.assertEqual(c['auth']['site_url'], 'https://shop.in')

    def test_half_a_google_pair_keeps_it_off(self):
        self.assertFalse(self.load({'GOOGLE_WEB_CLIENT_ID': 'x'})['auth']['external']['google']['enabled'])


class Env(unittest.TestCase):
    def test_parse(self):
        env = parse_env('# note\nA=1\nB = "two words"\nC=\n\nD=\'q\'\nE=a=b\n')
        self.assertEqual(env, {'A': '1', 'B': 'two words', 'C': '', 'D': 'q', 'E': 'a=b'})


class Site(unittest.TestCase):
    def test_fills_what_it_has_and_lists_the_rest(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'site'
            left = fill_site(ROOT / 'site', out, {'LEGAL_BUSINESS_NAME': 'Shyam Mobile Center', 'GSTIN': '23ABCDE1234F1Z5'})
            self.assertEqual(left, ['[[DELIVERY TIME]]', '[[GRIEVANCE OFFICER NAME]]', '[[SUPPORT EMAIL]]'])
            privacy = (out / 'privacy.html').read_text()
            self.assertIn('Shyam Mobile Center', privacy)
            self.assertIn('MSG91', privacy)
            self.assertNotIn('[[GSTIN]]', privacy)
            self.assertIn('[[LEGAL BUSINESS NAME]]', (ROOT / 'site/privacy.html').read_text())  # source untouched
            self.assertIn('package=com.shyammobiles.app', (out / 'open.html').read_text())  # the share-link page


UPLOAD = ':'.join(['AB'] * 32)
PLAY = ':'.join(['0F'] * 32)
KEYTOOL = f'Certificate fingerprints:\n\t SHA1: {":".join(["12"] * 20)}\n\t SHA256: {UPLOAD}\nSignature algorithm'


class ShareLinks(unittest.TestCase):
    def test_fingerprints_from_keytool(self):
        self.assertEqual(key_fingerprints(KEYTOOL), (':'.join(['12'] * 20), UPLOAD))
        self.assertEqual(key_fingerprints(''), (None, None))
        self.assertTrue(SHA256.match(UPLOAD))
        self.assertFalse(SHA256.match(UPLOAD[:-3]))

    def test_assetlinks_lists_every_signing_key_for_the_package(self):
        [entry] = json.loads(assetlinks([UPLOAD, PLAY]))
        self.assertEqual(entry['relation'], ['delegate_permission/common.handle_all_urls'])
        self.assertEqual(entry['target'], {'namespace': 'android_app', 'package_name': 'com.shyammobiles.app',
                                           'sha256_cert_fingerprints': [UPLOAD, PLAY]})

    def test_dry_run_site_waits_for_a_valid_play_key(self):
        launch = Launch({'PLAY_SIGNING_SHA256': 'not-a-key'}, dry=True)
        launch.site()
        self.assertTrue(any('PLAY_SIGNING_SHA256 should look like' in s for s in launch.skipped))


KEY = {'type': 'service_account', 'project_id': 'shyam-mobiles', 'client_email': 'push@shyam-mobiles.iam.gserviceaccount.com',
       'private_key': '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n'}


class Push(unittest.TestCase):
    def test_service_account_pasted_or_as_a_file_becomes_one_line(self):
        pasted = fcm_service_account(json.dumps(KEY, indent=2))
        self.assertNotIn('\n', pasted.replace('\\n', ''))  # one line for the secrets file; the key keeps its \n escapes
        self.assertEqual(json.loads(pasted), KEY)
        with tempfile.NamedTemporaryFile('w', suffix='.json') as f:
            json.dump(KEY, f)
            f.flush()
            self.assertEqual(fcm_service_account(f.name), pasted)
        with self.assertRaises(ValueError):
            fcm_service_account('{"project_id": "x"}')  # the google-services.json or web config, not the key

    def test_vault_sql_points_the_database_at_send_push(self):
        sql = push_vault_sql('abcdefghijklmnopqrst', 'S' * 43)
        self.assertIn("'https://abcdefghijklmnopqrst.supabase.co/functions/v1/send-push', 'push_url'", sql)
        self.assertIn("vault.update_secret(id, '" + 'S' * 43 + "') from vault.secrets where name = 'push_secret'", sql)
        with self.assertRaises(ValueError):
            push_vault_sql("x'; drop table orders; --", 'S' * 43)

    def test_dry_run_sets_both_push_secrets_and_waits_for_the_app_keys(self):
        launch = Launch({**BASE, 'FCM_SERVICE_ACCOUNT': json.dumps(KEY)}, dry=True)
        launch.secrets()
        self.assertIsNotNone(launch.push_secret)
        launch.push()
        self.assertTrue(any('FIREBASE_* keys' in s for s in launch.skipped))
        self.assertFalse(any(s.startswith('push: phone notifications need') for s in launch.skipped))


if __name__ == '__main__':
    unittest.main()
