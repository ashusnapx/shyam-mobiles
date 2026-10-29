"""python3 -m unittest scripts/test_launch.py — checks the production config and policy pages launch.py writes."""
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from launch import ROOT, fill_site, parse_env, prod_config  # noqa: E402

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


if __name__ == '__main__':
    unittest.main()
