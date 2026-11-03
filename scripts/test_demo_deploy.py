"""demo_deploy: re-running it never resets a demo password that still works (that signs the demo phone out)."""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent))
import demo_deploy  # noqa: E402


class Accounts(unittest.TestCase):
    def run_accounts(self, sign_in_works):
        d = demo_deploy.Deploy.__new__(demo_deploy.Deploy)  # no local.env
        d.url, d.env, d._secret = 'https://x.supabase.co', {'SUPABASE_PUBLISHABLE_KEY': 'pk'}, 'sk'
        d.state = {'customer_password': 'c', 'admin_password': 'a'}
        users = {'users': [{'email': e, 'id': f'id-{r}'} for r, (e, _) in demo_deploy.DEMO.items()]}
        calls = []

        def http(method, url, key, body=None, headers=None):
            calls.append((method, url.split('/v1/')[-1]))
            if method == 'GET':
                return users
            if 'grant_type=password' in url:
                return {'access_token': 't'} if sign_in_works else {'_error': 400}
            return {}
        with mock.patch.object(demo_deploy, 'http', http), mock.patch('builtins.print'):
            d.accounts()
        return [c for c in calls if c[0] == 'PUT']

    def test_working_password_is_left_alone(self):
        self.assertEqual(self.run_accounts(sign_in_works=True), [])

    def test_changed_password_is_set(self):
        self.assertEqual(len(self.run_accounts(sign_in_works=False)), 2)


if __name__ == '__main__':
    unittest.main()
