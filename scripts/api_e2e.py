#!/usr/bin/env python3
"""Attack + end-to-end suite for the Shyam Mobiles backend, over the real HTTP APIs of the LOCAL stack.

  python3 scripts/dev_setup.py                        # once, and after every `supabase-go db reset`
  supabase-go functions serve --env-file <file>       # file with FAKE values (defaults below) for the Edge Function checks
  python3 scripts/api_e2e.py

Acts as anon, customers (alice, bob, carol, dave: created here) and staff (the dev admin account) against
PostgREST, RPCs, Storage, Auth and Edge Functions, and checks every number the server stores. Stdlib only.
Refuses any API/DB URL that isn't 127.0.0.1/localhost. Everything it creates is tagged e2e-<run> and deleted at
the end (store_settings are restored), so it can be re-run; GoTrue allows 20 sign-ins per 5 min per IP, and a run
uses about 8. It never touches the dev customer account. Edge Function secrets it signs with (fake, local):
RAZORPAY_KEY_SECRET=fake_secret_for_tests, RAZORPAY_WEBHOOK_SECRET=whsec_local_tests (override with E2E_<NAME>).
It never makes a function call Razorpay's real API. Prints PASS/FAIL per check, exits 1 if any failed.
"""
import base64
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUN = secrets.token_hex(3)
KEY_SECRET = os.environ.get('E2E_RAZORPAY_KEY_SECRET', 'fake_secret_for_tests')
WEBHOOK_SECRET = os.environ.get('E2E_RAZORPAY_WEBHOOK_SECRET', 'whsec_local_tests')
FEE, FREE_MIN = 4900, 100000  # delivery settings used for the whole run
REFUND_NOTE = 'A full refund to your original payment method is on its way; banks usually take 5–7 working days.'


def stack_env() -> dict:
    out = subprocess.run(['supabase-go', 'status', '-o', 'env'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return {k: v.strip('"') for k, _, v in (line.partition('=') for line in out.splitlines()) if v}


ENV = stack_env()
API = ENV['API_URL']
for url in (API, ENV['DB_URL']):
    host = urllib.parse.urlsplit(url).hostname
    if host not in ('127.0.0.1', 'localhost'):
        sys.exit(f'refusing: {host} is not the local stack')
PUB = ENV.get('PUBLISHABLE_KEY') or ENV['ANON_KEY']
SECRET = ENV.get('SECRET_KEY') or ENV['SERVICE_ROLE_KEY']
DEV = json.loads((ROOT / 'app' / 'env' / 'dev.json').read_text())

# --- reporting ------------------------------------------------------------------------------------------

FAILS: list[str] = []


def check(name: str, ok, detail='') -> bool:
    print(('PASS  ' if ok else 'FAIL  ') + name + ('' if ok else f'  -- {str(detail)[:300]}'), flush=True)
    if not ok:
        FAILS.append(name)
    return bool(ok)


def section(title: str) -> None:
    print(f'\n== {title}', flush=True)


# --- HTTP ---------------------------------------------------------------------------------------------

Res = namedtuple('Res', 'status body headers')


def http(method, path, body=None, *, key=PUB, token=None, headers=None, raw=None) -> Res:
    h = {'apikey': key} if key else {}
    if token:
        h['Authorization'] = 'Bearer ' + token
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    if data is not None:
        h['Content-Type'] = 'application/json'
    h.update(headers or {})
    req = urllib.request.Request(API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            status, text, hdrs = r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        status, text, hdrs = e.code, e.read(), e.headers
    try:
        parsed = json.loads(text) if text else None
    except ValueError:
        parsed = text
    return Res(status, parsed, hdrs)


def code(res: Res):
    """The bare error code of a PostgREST/RPC/function error, else None."""
    b = res.body
    return (b.get('message') if 'code' in b else b.get('error')) if isinstance(b, dict) else None


def denied(res: Res) -> bool:
    return res.status in (401, 403) or (res.status == 404 and isinstance(res.body, dict) and res.body.get('code') == 'PGRST202')


class Actor:
    def __init__(self, name, token=None, uid=None, key=PUB):
        self.name, self.token, self.uid, self.key = name, token, uid, key

    def req(self, method, path, body=None, **kw):
        return http(method, path, body, key=self.key, token=self.token, **kw)

    def get(self, path, **kw):
        return self.req('GET', '/rest/v1/' + path, **kw)

    def post(self, table, body, prefer='return=representation', **kw):
        return self.req('POST', '/rest/v1/' + table, body, headers={'Prefer': prefer, **kw.pop('headers', {})}, **kw)

    def patch(self, path, body):
        return self.req('PATCH', '/rest/v1/' + path, body, headers={'Prefer': 'return=representation'})

    def delete(self, path):
        return self.req('DELETE', '/rest/v1/' + path, headers={'Prefer': 'return=representation'})

    def rpc(self, fn, args=None):
        return self.req('POST', '/rest/v1/rpc/' + fn, args or {})

    def fn(self, name, body=None, **kw):
        return self.req('POST', '/functions/v1/' + name, {} if body is None else body, **kw)

    def one(self, path):
        r = self.get(path)
        assert r.status == 200 and len(r.body) == 1, f'{self.name} GET {path}: {r.status} {r.body}'
        return r.body[0]


ANON = Actor('anon')
SVC = Actor('service', key=SECRET)  # secret key: service_role, bypasses RLS (fixtures and inspection only)


def sign_in(email, password, name) -> Actor:
    r = http('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': password})
    assert r.status == 200, f'sign-in {name}: {r.status} {r.body}'
    return Actor(name, r.body['access_token'], r.body['user']['id'])


CREATED_USERS: list[str] = []


def new_customer(name) -> Actor:
    email, password = f'e2e-{RUN}-{name}@shyammobiles.test', secrets.token_urlsafe(18)
    r = http('POST', '/auth/v1/admin/users', {'email': email, 'password': password, 'email_confirm': True}, key=SECRET)
    assert r.status == 200, f'create {name}: {r.status} {r.body}'
    CREATED_USERS.append(r.body['id'])
    return sign_in(email, password, name)


# --- JWT helpers (forging attempts) ----------------------------------------------------------------------

def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


def b64d(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def jwt(payload: dict, secret: str | None, alg='HS256') -> str:
    head = b64u(json.dumps({'alg': alg, 'typ': 'JWT'}).encode()) + '.' + b64u(json.dumps(payload).encode())
    sig = b64u(hmac.new(secret.encode(), head.encode(), hashlib.sha256).digest()) if secret else ''
    return head + '.' + sig


def tamper(token: str, **claims) -> str:
    h, p, s = token.split('.')
    return h + '.' + b64u(json.dumps({**json.loads(b64d(p)), **claims}).encode()) + '.' + s


# --- fixtures -----------------------------------------------------------------------------------------

PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
ORDERS: list[str] = []  # every order created, for the final numbers audit
REPAIRS: list[str] = []
V: dict[str, str] = {}  # variant key -> id
P: dict[str, str] = {}  # product key -> id
GST = {'phone': 18, 'acc': 12, 'retired': 18}
EVENT_SEQ = iter(range(1, 10**6))


def address(actor: Actor) -> str:
    r = actor.post('addresses', {'user_id': actor.uid, 'name': actor.name.title(), 'phone': '+919876543210',
                                 'line1': '1 Rajeev Complex', 'city': 'Waidhan', 'state': 'Madhya Pradesh', 'pincode': '486886'})
    assert r.status == 201, r
    return r.body[0]['id']


def set_cart(actor: Actor, lines: dict) -> None:
    actor.delete(f'cart_items?user_id=eq.{actor.uid}')
    if lines:
        r = actor.post('cart_items', [{'user_id': actor.uid, 'variant_id': V[k], 'qty': q} for k, q in lines.items()])
        assert r.status == 201, r


def place(actor: Actor, addr: str, method: str) -> Res:
    r = actor.rpc('place_order', {'p_address_id': addr, 'p_payment_method': method})
    if r.status == 200 and isinstance(r.body, str):
        ORDERS.append(r.body)
    return r


def stock(key: str) -> int:
    return SVC.one(f'variants?id=eq.{V[key]}&select=stock')['stock']


def order(oid: str) -> dict:
    return SVC.one(f'orders?id=eq.{oid}&select=*,order_items(*),order_events(status,note,id)')


def timeline(oid: str) -> list:
    return [(e['status'], e['note']) for e in sorted(order(oid)['order_events'], key=lambda e: e['id'])]


def staff_update(staff, oid, status, note=None, courier=None, tracking=None) -> Res:
    return staff.rpc('admin_update_order', {'p_order_id': oid, 'p_status': status, 'p_note': note,
                                             'p_courier': courier, 'p_tracking_number': tracking})


def set_rzp(oid: str) -> str:
    """Stands in for create-payment's Razorpay call: give the order a Razorpay order id."""
    rzp = f'order_e2e{RUN}{len(ORDERS)}{secrets.token_hex(2)}'
    assert SVC.patch(f'orders?id=eq.{oid}', {'razorpay_order_id': rzp}).status == 200
    return rzp


def webhook(body, event_id=None, signature=None) -> Res:
    raw = body if isinstance(body, bytes) else json.dumps(body).encode()
    sig = hmac.new(WEBHOOK_SECRET.encode(), raw, hashlib.sha256).hexdigest() if signature is None else signature
    headers = {'x-razorpay-signature': sig}
    if event_id is not False:
        headers['x-razorpay-event-id'] = event_id or f'evt_e2e_{RUN}_{next(EVENT_SEQ)}'
    return http('POST', '/functions/v1/razorpay-webhook', raw=raw, headers=headers)


def captured(rzp, pay, amount, event='payment.captured'):
    return {'event': event, 'payload': {'payment': {'entity': {'id': pay, 'order_id': rzp, 'amount': amount, 'status': 'captured', 'notes': {}}}}}


def refund_event(pay, amount, refunded, with_payment=True):
    payload = {'refund': {'entity': {'id': 'rfnd_' + pay, 'payment_id': pay, 'amount': refunded}}}
    if with_payment:
        payload['payment'] = {'entity': {'id': pay, 'amount': amount, 'amount_refunded': refunded}}
    return {'event': 'refund.processed', 'payload': payload}


def dashboard(staff) -> dict:
    r = staff.rpc('admin_dashboard')
    assert r.status == 200, r
    return r.body


def no_leak(res: Res) -> bool:
    text = json.dumps(res.body).lower() if not isinstance(res.body, bytes) else res.body.decode(errors='replace').lower()
    return not any(w in text for w in ('postgres', 'sql', 'stack', 'syntax', 'relation', 'constraint', 'violates', '.ts:', 'at async', 'supabase_'))


# --- sections -----------------------------------------------------------------------------------------

def setup_catalog(staff: Actor) -> None:
    cat = staff.post('categories', {'slug': f'e2e-{RUN}', 'name': f'E2E {RUN}', 'kind': 'phone'})
    brand = staff.post('brands', {'slug': f'e2e-{RUN}', 'name': f'E2E {RUN}'})
    assert cat.status == brand.status == 201, (cat, brand)
    for key, active in (('phone', True), ('acc', True), ('retired', False)):
        r = staff.post('products', {'slug': f'e2e-{RUN}-{key}', 'name': f'E2E {RUN} {key}', 'brand_id': brand.body[0]['id'],
                                    'category_id': cat.body[0]['id'], 'gst_rate': GST[key], 'is_active': active})
        assert r.status == 201, r
        P[key] = r.body[0]['id']
    rows = {  # key: (product, price, mrp, stock, active)
        'a': ('phone', 99999, 120000, 50, True),      # just under free delivery
        'b': ('phone', 100000, 120000, 50, True),     # exactly the free-delivery minimum
        'c': ('phone', 20000, 30000, 100, True),
        'cheap': ('phone', 100, 100, 50, True),
        'last': ('phone', 30000, 30000, 1, True),
        'off': ('phone', 10000, 10000, 5, False),
        'big': ('phone', 2147483647, 2147483647, 10, True),  # int max
        'race': ('phone', 5000, 5000, 200, True),
        'g12': ('acc', 49900, 59900, 20, True),
        'retired': ('retired', 10000, 10000, 5, True),
    }
    for key, (prod, price, mrp, qty, active) in rows.items():
        r = staff.post('variants', {'product_id': P[prod], 'sku': f'e2e-{RUN}-{key}', 'name': key, 'price_paise': price,
                                    'mrp_paise': mrp, 'stock': qty, 'is_active': active})
        assert r.status == 201, r
        V[key] = r.body[0]['id']
    r = staff.post('variants', [{'product_id': P['phone'], 'sku': f'e2e-{RUN}-l{n:02}', 'name': f'l{n:02}', 'price_paise': 100,
                                 'mrp_paise': 100, 'stock': 10} for n in range(1, 22)])  # l01..l21 for the line caps
    assert r.status == 201, r
    V.update({row['name']: row['id'] for row in r.body})


def anon_checks(alice_order: str) -> None:
    section('anon')
    for t in ('profiles', 'admins', 'wishlist', 'cart_items', 'addresses', 'orders', 'order_items', 'order_events',
              'payment_events', 'repair_bookings'):
        r = ANON.get(f'{t}?select=*&limit=1')
        check(f'anon cannot read {t}', r.status == 401, r)
    r = ANON.get(f'products?select=id&id=in.({P["phone"]},{P["retired"]})')
    check('anon sees active products only', [x['id'] for x in r.body] == [P['phone']], r)
    r = ANON.get(f'products?select=id,variants(id)&id=eq.{P["phone"]}')
    check('anon embed hides inactive variants', V['off'] not in {v['id'] for v in r.body[0]['variants']}, r)
    r = ANON.get(f'variants?id=in.({V["off"]},{V["retired"]})')
    check('anon cannot read inactive variants or variants of inactive products', r.body == [], r)
    r = ANON.get('product_cards?select=id&limit=100000')
    check('huge limit is capped at max_rows (1000)', r.status == 200 and len(r.body) <= 1000, r.status)
    r = ANON.post('brands', {'slug': f'e2e-{RUN}-anon', 'name': 'x'})
    check('anon cannot write the catalog', r.status == 401, r)
    r = ANON.patch('store_settings?id=eq.true', {'cod_max_paise': 1})
    check('anon cannot edit store_settings', r.status == 401, r)
    for fn, args in (('place_order', {'p_address_id': alice_order, 'p_payment_method': 'cod'}),
                     ('cancel_order', {'p_order_id': alice_order}), ('is_admin', {}), ('admin_dashboard', {}),
                     ('mark_order_paid', {'p_order_id': alice_order, 'p_razorpay_payment_id': 'pay_x'}),
                     ('expire_unpaid_orders', {}), ('restock_order', {'p_order_id': alice_order})):
        r = ANON.rpc(fn, args)
        check(f'anon cannot call {fn}', denied(r), r)
    r = http('POST', '/graphql/v1', {'query': '{ ordersCollection(first: 5) { edges { node { id } } } }'})
    data = r.body.get('data') if isinstance(r.body, dict) else None
    check('anon GraphQL cannot reach orders', not (data and data.get('ordersCollection')), r)


def customer_checks(alice: Actor, bob: Actor, staff: Actor, a_addr: str, b_addr: str, b_order: str, a_order: str) -> None:
    section('customer authz (alice vs bob)')
    for t, col in (('cart_items', 'user_id'), ('wishlist', 'user_id'), ('addresses', 'user_id'), ('orders', 'user_id'),
                   ('repair_bookings', 'user_id'), ('profiles', 'id')):
        r = alice.get(f'{t}?{col}=eq.{bob.uid}')
        check(f"alice cannot read bob's {t}", r.status == 200 and r.body == [], r)
    r = alice.get(f'order_items?order_id=eq.{b_order}')
    check("alice cannot read bob's order_items", r.body == [], r)
    r = alice.get(f'order_events?order_id=eq.{b_order}')
    check("alice cannot read bob's order_events", r.body == [], r)
    r = alice.get(f'orders?select=id&or=(user_id.eq.{bob.uid},user_id.is.null,id.eq.{b_order})')
    check('or= filter cannot widen RLS', r.body == [], r)
    r = alice.get('orders?select=id,user_id,order_items(id),order_events(id)')
    check('embeds stay inside her own orders', r.status == 200 and {o['user_id'] for o in r.body} == {alice.uid}, r)
    r = alice.get(f'variants?select=id,cart_items(user_id)&id=in.({V["c"]},{V["a"]})')
    check('variant -> cart_items embed shows only her lines', all(ci['user_id'] == alice.uid for v in r.body for ci in v['cart_items']), r)
    r = alice.get(f'products?select=id,wishlist(user_id)&id=eq.{P["phone"]}')
    check('product -> wishlist embed shows only her rows', all(w['user_id'] == alice.uid for p in r.body for w in p['wishlist']), r)
    r = alice.get('orders?select=id', headers={'Prefer': 'count=exact'})
    total = int(r.headers.get('Content-Range', '*/-1').split('/')[-1])
    check('Prefer: count=exact counts only her orders', total == len(r.body) and all(o['id'] != b_order for o in r.body), r.headers.get('Content-Range'))
    r = alice.get(f'orders?select=id&order=user_id.desc,razorpay_payment_id.asc,reserved_until.desc&id=eq.{b_order}')
    check('ordering by other columns leaks nothing', r.body == [], r)

    # writes into bob's rows
    r = alice.post('cart_items', {'user_id': bob.uid, 'variant_id': V['c'], 'qty': 1})
    check("alice cannot add to bob's cart", r.status == 403, r)
    r = alice.patch(f'cart_items?user_id=eq.{bob.uid}', {'qty': 5})
    check("alice cannot edit bob's cart", r.body == [], r)
    r = alice.delete(f'addresses?id=eq.{b_addr}')
    check("alice cannot delete bob's address", r.body == [] and len(bob.get(f'addresses?id=eq.{b_addr}').body) == 1, r)
    r = alice.patch(f'addresses?id=eq.{a_addr}', {'user_id': bob.uid})
    check('alice cannot move her address to bob', r.status == 403, r)
    r = alice.post('wishlist', {'user_id': bob.uid, 'product_id': P['phone']})
    check("alice cannot write bob's wishlist", r.status == 403, r)
    r = alice.patch(f'profiles?id=eq.{bob.uid}', {'full_name': 'pwned'})
    check("alice cannot edit bob's profile", r.body == [], r)

    # clients never write orders/payments/admins
    rows = {'orders': {'user_id': alice.uid, 'status': 'confirmed', 'payment_method': 'cod', 'subtotal_paise': 1, 'total_paise': 1, 'address': {}},
            'order_items': {'order_id': a_order, 'product_name': 'x', 'variant_name': 'x', 'unit_price_paise': 1, 'qty': 1, 'gst_rate': 0},
            'order_events': {'order_id': a_order, 'status': 'delivered', 'note': 'x'},
            'payment_events': {'razorpay_event_id': f'evt_fake_{RUN}', 'type': 'payment.captured', 'payload': {}},
            'admins': {'user_id': alice.uid}}
    for t, row in rows.items():
        r = alice.post(t, row)
        check(f'alice cannot insert {t}', r.status == 403, r)
    r = alice.patch(f'orders?id=eq.{a_order}', {'total_paise': 1, 'subtotal_paise': 1, 'status': 'delivered'})
    check('alice cannot update her order', r.status == 403, r)
    r = alice.patch(f'order_items?order_id=eq.{a_order}', {'unit_price_paise': 1})
    check('alice cannot update her order items', r.status == 403, r)
    r = alice.delete(f'orders?id=eq.{a_order}')
    check('alice cannot delete her order', r.status == 403, r)
    r = alice.get('admins?select=*')
    check('alice cannot read admins', r.status == 403, r)
    r = alice.get('payment_events?select=*')
    check('alice cannot read payment_events', r.status == 403, r)

    # catalog and settings
    before = SVC.one('store_settings?select=*')
    r = alice.patch('store_settings?id=eq.true', {'cod_max_paise': 99999999, 'delivery_fee_paise': 0})
    check('alice cannot edit store_settings', r.body == [] and SVC.one('store_settings?select=*') == before, r)
    r = alice.post('products', {'slug': f'e2e-{RUN}-evil', 'name': 'Evil', 'brand_id': SVC.one(f'products?id=eq.{P["phone"]}')['brand_id'],
                                'category_id': SVC.one(f'products?id=eq.{P["phone"]}')['category_id']})
    check('alice cannot create products', r.status == 403, r)
    r = alice.patch(f'variants?id=eq.{V["c"]}', {'price_paise': 1, 'stock': 9999})
    check('alice cannot change prices or stock', r.body == [] and SVC.one(f'variants?id=eq.{V["c"]}')['price_paise'] == 20000, r)
    r = alice.delete(f'products?id=eq.{P["phone"]}')
    check('alice cannot delete products', r.body == [], r)
    r = alice.post('product_images', {'product_id': P['phone'], 'path': 'evil.png'})
    check('alice cannot add product images', r.status == 403, r)

    # column-level escapes and mass assignment
    r = alice.patch(f'profiles?id=eq.{alice.uid}', {'full_name': 'Alice E2E', 'phone': '+919812345678'})
    check('alice edits her name and phone', r.status == 200 and r.body[0]['full_name'] == 'Alice E2E', r)
    for col, val in (('id', bob.uid), ('created_at', '2000-01-01T00:00:00Z'), ('updated_at', '2000-01-01T00:00:00Z')):
        r = alice.patch(f'profiles?id=eq.{alice.uid}', {col: val})
        check(f'alice cannot set profiles.{col}', r.status in (400, 403), r)
    r = alice.post('cart_items', {'user_id': alice.uid, 'variant_id': V['cheap'], 'qty': 1, 'price_paise': 1})
    check('extra JSON fields (price) are rejected, not stored', r.status == 400, r)
    for qty in (0, 6, -1, 1.5, 2147483648, 'abc'):
        r = alice.post('cart_items', {'user_id': alice.uid, 'variant_id': V['cheap'], 'qty': qty})
        check(f'cart qty {qty!r} rejected', r.status == 400, r)
    set_cart(alice, {'cheap': 1})
    r = alice.patch(f'cart_items?user_id=eq.{alice.uid}', {'qty': 6})
    check('cart qty cannot be raised above 5', r.status == 400, r)
    set_cart(alice, {})

    today = time.strftime('%Y-%m-%d', time.gmtime(time.time() + 19800))
    repair = {'user_id': alice.uid, 'device_brand': 'Samsung', 'device_model': 'A15', 'issue': 'screen',
              'preferred_date': today, 'slot': 'morning', 'contact_phone': '+919876543210'}
    for extra, label in (({'status': 'completed'}, 'status'), ({'quote_paise': 1}, 'quote_paise'),
                         ({'admin_note': 'free'}, 'admin_note'), ({'user_id': bob.uid}, "bob's user_id"),
                         ({'number': f'RP9{RUN}'}, 'number'), ({'created_at': '2000-01-01T00:00:00Z'}, 'created_at'),
                         ({'preferred_date': '2000-01-01'}, 'a past date'),
                         ({'preferred_date': time.strftime('%Y-%m-%d', time.gmtime(time.time() + 19800 + 31 * 86400))}, 'a date > 30 days out')):
        r = alice.post('repair_bookings', {**repair, **extra})
        check(f'repair insert cannot set {label}', r.status in (400, 403), r)
    b_rep = bob.post('repair_bookings', {**repair, 'user_id': bob.uid})
    assert b_rep.status == 201, b_rep
    b_rep = b_rep.body[0]
    r = alice.post('repair_bookings', {**repair, 'id': b_rep['id']}, prefer='return=representation,resolution=merge-duplicates')
    check("alice cannot upsert over bob's repair", r.status in (403, 409) and bob.one(f'repair_bookings?id=eq.{b_rep["id"]}') == b_rep, r)
    r = alice.rpc('cancel_repair', {'p_booking_id': b_rep['id']})
    check("alice cannot cancel bob's repair", code(r) == 'NOT_FOUND', r)

    # RPCs with other people's ids, staff-only and service-only RPCs
    r = alice.rpc('cancel_order', {'p_order_id': b_order})
    check("alice cannot cancel bob's order", code(r) == 'NOT_FOUND', r)
    r = alice.rpc('place_order', {'p_address_id': b_addr, 'p_payment_method': 'cod'})
    check("alice cannot ship to bob's address", code(r) in ('ADDRESS_NOT_FOUND', 'CART_EMPTY'), r)
    set_cart(alice, {'cheap': 1})
    r = alice.rpc('place_order', {'p_address_id': b_addr, 'p_payment_method': 'cod'})
    check("place_order with bob's address id -> ADDRESS_NOT_FOUND", code(r) == 'ADDRESS_NOT_FOUND', r)
    set_cart(alice, {})
    for fn, args in (('admin_update_order', {'p_order_id': b_order, 'p_status': 'cancelled'}),
                     ('admin_set_imeis', {'p_order_item_id': a_order, 'p_imeis': ['1' * 15]}), ('admin_dashboard', {})):
        r = alice.rpc(fn, args)
        check(f'alice gets FORBIDDEN from {fn}', code(r) == 'FORBIDDEN', r)
    for fn, args in (('mark_order_paid', {'p_order_id': a_order, 'p_razorpay_payment_id': f'pay_{RUN}'}),
                     ('mark_payment_failed', {'p_order_id': b_order}), ('mark_order_refunded', {'p_razorpay_payment_id': 'pay_x'}),
                     ('expire_unpaid_orders', {}), ('restock_order', {'p_order_id': a_order}),
                     ('handle_new_user', {}), ('addresses_before_write', {})):
        r = alice.rpc(fn, args)
        check(f'alice cannot call {fn}', denied(r), r)
        r = staff.rpc(fn, args)
        check(f'staff cannot call {fn}', denied(r), r)
    check('alice is not admin', alice.rpc('is_admin').body is False)
    r = http('PUT', '/auth/v1/user', {'data': {'role': 'service_role', 'is_admin': True}}, token=alice.token)
    check('user_metadata cannot grant staff rights', r.status == 200 and alice.rpc('is_admin').body is False, r)

    # address book limit
    for _ in range(len(alice.get('addresses?select=id').body), 10):
        address(alice)
    r = alice.post('addresses', {'user_id': alice.uid, 'name': 'Eleven', 'phone': '+919876543210', 'line1': '11 Road',
                                 'city': 'Waidhan', 'state': 'MP', 'pincode': '486886'})
    check('11th address -> ADDRESS_LIMIT', code(r) == 'ADDRESS_LIMIT', r)
    alice.delete(f'addresses?user_id=eq.{alice.uid}&id=neq.{a_addr}')


def staff_checks(staff: Actor, alice: Actor) -> None:
    section('staff')
    check('staff is admin', staff.rpc('is_admin').body is True)
    r = staff.get(f'orders?select=id&user_id=eq.{alice.uid}')
    check('staff reads every order', r.status == 200 and len(r.body) >= 1, r)
    some = r.body[0]['id']
    r = staff.patch(f'orders?id=eq.{some}', {'status': 'delivered'})
    check('staff cannot update orders directly', r.status == 403, r)
    r = staff.post('payment_events', {'razorpay_event_id': f'evt_staff_{RUN}', 'type': 'x', 'payload': {}})
    check('staff cannot insert payment_events', r.status == 403, r)
    r = staff.post('admins', {'user_id': alice.uid})
    check('staff cannot add admins', r.status == 403 and alice.rpc('is_admin').body is False, r)
    r = staff.get(f'profiles?id=eq.{alice.uid}')
    check("staff cannot read customers' profiles", r.body == [], r)


def storage_checks(staff: Actor, alice: Actor) -> list:
    section('storage (product-images)')
    paths = []

    def up(actor, path, data=PNG, ctype='image/png', upsert=False):
        h = {'Content-Type': ctype}
        if upsert:
            h['x-upsert'] = 'true'
        return actor.req('POST', f'/storage/v1/object/product-images/{path}', raw=data, headers=h)

    ok_path = f'e2e-{RUN}/ok.png'
    r = up(staff, ok_path)
    check('staff uploads a product image', r.status == 200, r)
    paths.append(ok_path)
    public = f'/storage/v1/object/public/product-images/{ok_path}'
    check('public URL serves it', http('GET', public, key=None).status == 200)
    for path in (f'e2e-{RUN}/alice.png', f'store/e2e-{RUN}.png', f'e2e-{RUN}/../../alice.png', ok_path):
        r = up(alice, path)
        check(f'alice cannot upload {path}', r.status >= 400, r)
    r = up(alice, ok_path, data=b'evil', upsert=True)
    check('alice cannot overwrite with x-upsert', r.status >= 400 and http('GET', public, key=None).body == PNG, r)
    r = up(ANON, f'e2e-{RUN}/anon.png')
    check('anon cannot upload', r.status >= 400, r)
    r = alice.req('DELETE', f'/storage/v1/object/product-images/{ok_path}')
    check('alice cannot delete it', http('GET', public, key=None).status == 200, r)
    r = alice.req('DELETE', '/storage/v1/object/product-images', {'prefixes': [ok_path]})
    check('alice cannot bulk-delete it', http('GET', public, key=None).status == 200, r)
    r = alice.req('POST', '/storage/v1/object/list/product-images', {'prefix': f'e2e-{RUN}/'})
    check('alice cannot list the bucket', r.status != 200 or r.body == [], r)
    for ctype, data in (('text/html', b'<script>alert(1)</script>'), ('image/svg+xml', b'<svg onload="alert(1)"/>'),
                        ('application/octet-stream', PNG)):
        r = up(staff, f'e2e-{RUN}/bad.{ctype.split("/")[1][:4]}', data=data, ctype=ctype)
        check(f'{ctype} refused', r.status >= 400, r)
    r = up(staff, f'e2e-{RUN}/big.png', data=b'\0' * (5 * 1024 * 1024 + 1))
    check('a file over 5 MB is refused', r.status >= 400, r.status)
    r = up(staff, f'e2e-{RUN}/../../escape.png')
    check('path traversal in an object name is refused or kept inside the bucket', r.status >= 400 or not http('GET', '/storage/v1/object/public/escape.png', key=None).status == 200, r)
    if r.status == 200:
        paths.append(f'e2e-{RUN}/../../escape.png')
    return paths


def money_checks(staff: Actor, alice: Actor, bob: Actor, carol: Actor, dave: Actor, addrs: dict) -> None:
    section('money: delivery fee, COD limit, stale prices, stock')
    aa = addrs['alice']

    def placed(lines, method, label, cust=alice, keep=False):
        set_cart(cust, lines)
        r = place(cust, addrs[cust.name], method)
        check(label, r.status == 200, r)
        if r.status != 200:
            return None
        o = order(r.body)
        if method == 'razorpay' and not keep:  # stay under PENDING_LIMIT
            cust.rpc('cancel_order', {'p_order_id': r.body})
        return o

    o = placed({'a': 1}, 'razorpay', 'subtotal 99,999 (one paisa under the free minimum) places')
    check('... pays the delivery fee', o and (o['subtotal_paise'], o['delivery_fee_paise'], o['total_paise']) == (99999, FEE, 99999 + FEE), o)
    o = placed({'b': 1}, 'razorpay', 'subtotal exactly at the free minimum places')
    check('... delivery is free at exactly free_delivery_min', o and (o['delivery_fee_paise'], o['total_paise']) == (0, 100000), o)
    o = placed({'b': 1, 'cheap': 1}, 'razorpay', 'subtotal one rupee over places')
    check('... free above the minimum', o and (o['subtotal_paise'], o['delivery_fee_paise'], o['total_paise']) == (100100, 0, 100100), o)
    o = placed({'cheap': 1}, 'razorpay', 'a ₹1 order places')
    check('... ₹1 + delivery', o and o['total_paise'] == 100 + FEE, o)

    # COD limit compares the total including delivery (SPEC: "total > cod_max_paise")
    staff.patch('store_settings?id=eq.true', {'cod_enabled': True, 'cod_max_paise': 99999 + FEE})
    o = placed({'a': 1}, 'cod', 'COD allowed when the total equals cod_max')
    check('... COD order starts confirmed/pending', o and (o['status'], o['payment_status'], o['reserved_until']) == ('confirmed', 'pending', None), o)
    staff.patch('store_settings?id=eq.true', {'cod_max_paise': 99999 + FEE - 1})
    set_cart(alice, {'a': 1})
    r = place(alice, aa, 'cod')
    check('COD refused when subtotal < cod_max but subtotal + delivery > cod_max', code(r) == 'COD_UNAVAILABLE', r)
    check('... the cart survives a refused checkout', len(alice.get('cart_items?select=variant_id').body) == 1)
    o = placed({'b': 1}, 'cod', 'COD allowed for a free-delivery total under the limit')
    staff.patch('store_settings?id=eq.true', {'cod_enabled': False})
    set_cart(alice, {'cheap': 1})
    check('COD refused when disabled', code(place(alice, aa, 'cod')) == 'COD_UNAVAILABLE')
    staff.patch('store_settings?id=eq.true', {'cod_enabled': True, 'cod_max_paise': 2500000})

    # stale price: the price at checkout wins, never the one seen when adding to cart
    set_cart(alice, {'c': 2})
    staff.patch(f'variants?id=eq.{V["c"]}', {'price_paise': 25000})
    r = place(alice, aa, 'razorpay')
    o = order(r.body) if r.status == 200 else None
    if o:
        alice.rpc('cancel_order', {'p_order_id': r.body})
    check('price raised after add-to-cart: order uses the new price', o and o['order_items'][0]['unit_price_paise'] == 25000 and o['subtotal_paise'] == 50000, o or r)
    staff.patch(f'variants?id=eq.{V["c"]}', {'price_paise': 20000})

    # unavailable lines
    for lines, label in (({'off': 1}, 'inactive variant'), ({'retired': 1}, 'variant of an inactive product'),
                         ({'last': 2}, 'qty above stock')):
        set_cart(alice, {'cheap': 1, **lines})
        r = place(alice, aa, 'cod')
        key = next(iter(lines))
        check(f'{label} -> OUT_OF_STOCK naming that variant', code(r) == 'OUT_OF_STOCK' and r.body.get('details') == V[key], r)
    set_cart(alice, {})
    check('empty cart -> CART_EMPTY', code(place(alice, aa, 'cod')) == 'CART_EMPTY')

    # int overflow: fails cleanly, no order, stock and cart untouched
    s0, n0 = stock('big'), len(SVC.get(f'orders?user_id=eq.{alice.uid}&select=id').body)
    set_cart(alice, {'big': 2})
    r = place(alice, aa, 'razorpay')
    check('2 × the int-max price -> ORDER_TOO_LARGE (no raw overflow), nothing written', code(r) == 'ORDER_TOO_LARGE' and stock('big') == s0
          and len(SVC.get(f'orders?user_id=eq.{alice.uid}&select=id').body) == n0 and len(alice.get('cart_items').body) == 1, r)
    r = staff.patch(f'variants?id=eq.{V["big"]}', {'price_paise': 2147483648, 'mrp_paise': 2147483648})
    check('prices beyond int range are refused', r.status == 400, r)
    o = placed({'big': 1}, 'razorpay', 'one unit at int max still places')
    check('... with exact totals', o and o['total_paise'] == 2147483647, o)

    # GST stored per item from the product
    o = placed({'g12': 1, 'cheap': 1}, 'razorpay', 'mixed-GST order places')
    check('... each line keeps its product GST rate', o and sorted(float(i['gst_rate']) for i in o['order_items']) == [12.0, 18.0], o)

    # cancel restocks exactly once
    s0 = stock('c')
    o = placed({'c': 3}, 'cod', 'COD order of 3 places')
    check('... stock taken', stock('c') == s0 - 3)
    check('customer cancel succeeds', alice.rpc('cancel_order', {'p_order_id': o['id']}).status in (200, 204))
    check('... stock back', stock('c') == s0)
    check('second cancel -> INVALID_TRANSITION', code(alice.rpc('cancel_order', {'p_order_id': o['id']})) == 'INVALID_TRANSITION')
    check('staff "cancel" of a cancelled order is a no-op', staff_update(staff, o['id'], 'cancelled').status in (200, 204))
    SVC.rpc('expire_unpaid_orders')
    check('... restocked exactly once', stock('c') == s0, stock('c'))

    # expiry restock
    s0 = stock('c')
    o = placed({'c': 2}, 'razorpay', 'online order holds stock', keep=True)
    check('... reserved for ~15 minutes', o and 14 * 60 < time.mktime(time.strptime(o['reserved_until'][:19], '%Y-%m-%dT%H:%M:%S')) - time.mktime(time.gmtime()) <= 15 * 60, o and o['reserved_until'])
    SVC.patch(f'orders?id=eq.{o["id"]}', {'reserved_until': '2000-01-01T00:00:00Z'})
    r = SVC.rpc('expire_unpaid_orders')
    check('expiry job cancels it', r.status == 200 and r.body >= 1 and order(o['id'])['status'] == 'cancelled', r)
    check('... stock released', stock('c') == s0)
    check('... timeline says why', timeline(o['id'])[-1] == ('cancelled', 'Payment not received in time'), timeline(o['id']))
    r = SVC.rpc('expire_unpaid_orders')
    check('... and the job does not touch it again', stock('c') == s0)

    # race for the last unit: four customers, one unit
    staff.patch(f'variants?id=eq.{V["last"]}', {'stock': 1})
    racers = [alice, bob, carol, dave]
    for c in racers:
        set_cart(c, {'last': 1})
    barrier = threading.Barrier(len(racers))

    def go(c):
        barrier.wait()
        return place(c, addrs[c.name], 'razorpay')

    with ThreadPoolExecutor(len(racers)) as ex:
        results = list(ex.map(go, racers))
    wins = [r for r in results if r.status == 200]
    check('4 parallel checkouts for the last unit: exactly one wins', len(wins) == 1 and all(code(r) == 'OUT_OF_STOCK' for r in results if r.status != 200), results)
    check('... stock is 0, never negative', stock('last') == 0)
    for c, r in zip(racers, results):
        set_cart(c, {})
        if r.status == 200:
            c.rpc('cancel_order', {'p_order_id': r.body})

    # same customer adds a line while checkout runs: no line may slip in unpriced
    slipped = []
    for _ in range(25):
        set_cart(alice, {'race': 1})
        gate = threading.Barrier(2)

        def checkout():
            gate.wait()
            return place(alice, aa, 'razorpay')

        def add_line():
            gate.wait()
            return alice.post('cart_items', {'user_id': alice.uid, 'variant_id': V['cheap'], 'qty': 1}, prefer='return=minimal')

        with ThreadPoolExecutor(2) as ex:
            f1, f2 = ex.submit(checkout), ex.submit(add_line)
            r = f1.result()
            f2.result()
        if r.status == 200:
            o = order(r.body)
            if sum(i['unit_price_paise'] * i['qty'] for i in o['order_items']) != o['subtotal_paise']:
                slipped.append(o['id'])
            alice.rpc('cancel_order', {'p_order_id': r.body})
    set_cart(alice, {})
    check('25 checkouts racing an add-to-cart: every order is fully priced', not slipped, slipped)


def function_checks(staff: Actor, alice: Actor, bob: Actor, addrs: dict) -> bool:
    section('edge functions')
    r = webhook({'event': 'e2e.ping', 'payload': {}})
    if not check('functions are served with the test webhook secret', r.status == 200 and r.body == {'result': 'ignored'},
                 f'{r.status} {r.body}: run `supabase-go functions serve --env-file <fake env>` (see the docstring)'):
        return False
    aa = addrs['alice']
    set_cart(alice, {'c': 1})
    rz = place(alice, aa, 'razorpay').body
    set_cart(alice, {'c': 1})
    cod = place(alice, aa, 'cod').body
    set_cart(bob, {'c': 1})
    bob_rz = place(bob, addrs['bob'], 'razorpay').body
    rzp, bob_rzp = set_rzp(rz), set_rzp(bob_rz)
    total = order(rz)['total_paise']

    # authentication
    now = int(time.time())
    claims = {'sub': alice.uid, 'role': 'authenticated', 'aud': 'authenticated', 'iss': f'{API}/auth/v1', 'iat': now, 'exp': now + 600}
    tokens = {
        'no Authorization header': None,
        'publishable key as bearer': PUB,
        'legacy anon JWT': ENV.get('ANON_KEY'),
        'garbage token': 'not.a.jwt',
        'alg none': jwt(claims, None, 'none'),
        'HS256 with a wrong secret': jwt(claims, 'wrong-secret-wrong-secret-wrong-secret!'),
        'expired HS256 (local legacy secret)': jwt({**claims, 'exp': now - 60, 'iat': now - 3600}, ENV['JWT_SECRET']),
        'HS256 with the legacy secret (JWKS only)': jwt(claims, ENV['JWT_SECRET']),
        "alice's ES256 token with sub swapped to bob": tamper(alice.token, sub=bob.uid),
    }
    for fn in ('create-payment', 'verify-payment', 'delete-account'):
        for label, tok in tokens.items():
            r = http('POST', f'/functions/v1/{fn}', {'order_id': rz}, token=tok)
            check(f'{fn}: {label} -> 401', r.status == 401, r)
    r = alice.req('GET', '/functions/v1/create-payment')
    check('GET -> 405', r.status == 405, r)

    # create-payment
    r = alice.fn('create-payment', {'order_id': bob_rz})
    check("create-payment for bob's order -> 404", r.status == 404 and code(r) == 'NOT_FOUND', r)
    r = alice.fn('create-payment', {'order_id': cod})
    check('create-payment for a COD order -> 409 ORDER_NOT_PAYABLE', r.status == 409 and code(r) == 'ORDER_NOT_PAYABLE', r)
    for body in ({}, {'order_id': 'x'}, {'order_id': 1}, [rz]):
        r = alice.fn('create-payment', body)
        check(f'create-payment bad body {json.dumps(body)} -> 400', r.status == 400 and code(r) == 'BAD_REQUEST', r)
    r = alice.req('POST', '/functions/v1/create-payment', raw=b'{not json')
    check('create-payment malformed JSON -> 400', r.status == 400, r)
    first, second = alice.fn('create-payment', {'order_id': rz}), alice.fn('create-payment', {'order_id': rz})
    check('create-payment reuses the Razorpay order (idempotent)', first.status == second.status == 200
          and first.body['razorpay_order_id'] == second.body['razorpay_order_id'] == rzp, (first, second))
    check('... amount = order total, INR, number and hold time', first.status == 200 and first.body['amount'] == total
          and first.body['currency'] == 'INR' and first.body['order_number'] == order(rz)['number']
          and first.body['key_id'].startswith('rzp_'), first)
    set_cart(alice, {'c': 1})
    exp = place(alice, aa, 'razorpay').body
    set_rzp(exp)
    SVC.patch(f'orders?id=eq.{exp}', {'reserved_until': '2000-01-01T00:00:00Z'})
    r = alice.fn('create-payment', {'order_id': exp})
    check('create-payment after the hold ran out -> 409 ORDER_EXPIRED', r.status == 409 and code(r) == 'ORDER_EXPIRED', r)
    SVC.rpc('expire_unpaid_orders')
    r = alice.fn('create-payment', {'order_id': exp})
    check('create-payment on the expired (cancelled) order -> 409 ORDER_NOT_PAYABLE', r.status == 409 and code(r) == 'ORDER_NOT_PAYABLE', r)

    # verify-payment (never reaches Razorpay's API here: every case is refused before the fetch)
    def sig(o, p, secret=KEY_SECRET):
        return hmac.new(secret.encode(), f'{o}|{p}'.encode(), hashlib.sha256).hexdigest()
    r = alice.fn('verify-payment', {'razorpay_order_id': rzp, 'razorpay_payment_id': 'pay_e2e', 'razorpay_signature': '0' * 64})
    check('verify-payment bad signature -> 400 BAD_SIGNATURE', r.status == 400 and code(r) == 'BAD_SIGNATURE', r)
    r = alice.fn('verify-payment', {'razorpay_order_id': rzp, 'razorpay_payment_id': 'pay_e2e', 'razorpay_signature': sig(rzp, 'pay_e2e', 'other')})
    check('verify-payment signature from another secret -> 400', r.status == 400, r)
    r = alice.fn('verify-payment', {'razorpay_order_id': bob_rzp, 'razorpay_payment_id': 'pay_e2e', 'razorpay_signature': sig(bob_rzp, 'pay_e2e')})
    check("verify-payment with bob's (validly signed) order -> 404", r.status == 404 and code(r) == 'NOT_FOUND', r)
    r = alice.fn('verify-payment', {'razorpay_order_id': rzp, 'razorpay_payment_id': 'pay_e2e', 'razorpay_signature': sig(rzp, 'pay_other')})
    check("verify-payment signature for another payment id -> 400", r.status == 400, r)
    r = alice.fn('verify-payment', {'razorpay_order_id': rzp})
    check('verify-payment missing fields -> 400', r.status == 400 and code(r) == 'BAD_REQUEST', r)
    check('... order still unpaid', order(rz)['payment_status'] == 'pending')

    # webhook
    body = captured(rzp, f'pay_{RUN}_1', total)
    check('webhook without signature -> 401', webhook(body, signature='').status == 401)
    check('webhook bad signature -> 401', webhook(body, signature='0' * 64).status == 401)
    check('webhook signed with another secret -> 401', webhook(body, signature=hmac.new(b'x', json.dumps(body).encode(), hashlib.sha256).hexdigest()).status == 401)
    r = webhook(body, event_id=False)
    check('webhook without event id -> 400', r.status == 400, r)
    r = webhook(b'{"event": ')
    check('webhook signed malformed body -> 400', r.status == 400, r)
    r = webhook({'event': 'payment.dispute.created', 'payload': {}})
    check('unknown event -> 200 ignored', r.status == 200 and r.body == {'result': 'ignored'}, r)
    r = webhook(captured('order_nope', 'pay_nope', 100))
    check('unknown order -> 200 unknown_order', r.status == 200 and r.body == {'result': 'unknown_order'}, r)
    r = webhook(captured(rzp, f'pay_{RUN}_1', total - 1))
    check('valid signature, amount ≠ total -> not paid', r.body == {'result': 'amount_mismatch'} and order(rz)['payment_status'] == 'pending', r)
    r = webhook(captured(rzp, f'pay_{RUN}_1', str(total)))
    check('amount as a string -> not paid', r.body == {'result': 'amount_mismatch'} and order(rz)['payment_status'] == 'pending', r)
    r = webhook({'event': 'payment.failed', 'payload': {'payment': {'entity': {'id': f'pay_{RUN}_0', 'order_id': rzp}}}})
    check('payment.failed -> failed, still payable', r.body == {'result': 'failed'} and (order(rz)['status'], order(rz)['payment_status']) == ('pending_payment', 'failed'), r)
    evt = f'evt_e2e_{RUN}_paid'
    r = webhook(body, event_id=evt)
    o = order(rz)
    check('payment.captured -> confirmed + paid', r.body == {'result': 'paid'} and (o['status'], o['payment_status'], o['razorpay_payment_id'], o['reserved_until']) == ('confirmed', 'paid', f'pay_{RUN}_1', None), (r, o))
    check('replayed event id -> 200 duplicate', webhook(body, event_id=evt).body == {'result': 'duplicate'})
    r = webhook(body)
    check('same body, new event id -> idempotent', r.body == {'result': 'paid'} and timeline(rz).count(('confirmed', 'Payment received')) == 1, timeline(rz))
    r = webhook(captured(rzp, f'pay_{RUN}_2', total, 'order.paid'))
    check('order.paid with a second payment id does not overwrite the first', order(rz)['razorpay_payment_id'] == f'pay_{RUN}_1', r)
    r = webhook({'event': 'payment.captured', 'payload': {'payment': {'entity': {'id': f'pay_{RUN}_4', 'order_id': None, 'amount': order(cod)['total_paise'], 'notes': {'order_id': cod}}}}})
    check('a payment pointed at a COD order is refused', r.body == {'result': 'invalid_transition'} and order(cod)['payment_status'] == 'pending', r)
    for res in (webhook(body, signature=''), webhook(b'{"event": '), alice.fn('create-payment', {'order_id': bob_rz}),
                alice.fn('verify-payment', {}), alice.fn('create-payment', {'order_id': exp})):
        check(f'error body has no internals ({res.status})', no_leak(res) and (set(res.body) <= {'error', 'message', 'msg', 'code'} if isinstance(res.body, dict) else False), res)
    return True


def lifecycle(staff: Actor, alice: Actor, bob: Actor, addrs: dict, functions: bool) -> None:
    section('lifecycle: COD')
    aa = addrs['alice']
    set_cart(alice, {'c': 2})
    cod = place(alice, aa, 'cod').body
    item = order(cod)['order_items'][0]
    check('confirmed -> shipped (skipping packed) refused', code(staff_update(staff, cod, 'shipped')) == 'INVALID_TRANSITION')
    check('confirmed -> delivered refused', code(staff_update(staff, cod, 'delivered')) == 'INVALID_TRANSITION')
    for imeis, label in ((['1' * 15], 'fewer IMEIs than qty'), (['1' * 15, '1' * 15], 'duplicate IMEIs'),
                         (['1' * 15, '2' * 14], 'a 14-digit IMEI'), (['1' * 15, '2' * 15 + 'x'], 'a non-digit IMEI'),
                         ([['1' * 15, '2' * 15]], 'a 2-D array'), (['1' * 15, None], 'a null IMEI')):
        r = staff.rpc('admin_set_imeis', {'p_order_item_id': item['id'], 'p_imeis': imeis})
        check(f'IMEIs refused: {label}', code(r) == 'INVALID_IMEIS', r)
    imeis = ['356938035643809', '356938035643817']
    check('valid IMEIs saved', staff.rpc('admin_set_imeis', {'p_order_item_id': item['id'], 'p_imeis': imeis}).status in (200, 204)
          and alice.one(f'order_items?id=eq.{item["id"]}')['imeis'] == imeis)
    check('confirmed -> packed', staff_update(staff, cod, 'packed').status in (200, 204))
    check('packed -> shipped with courier', staff_update(staff, cod, 'shipped', None, 'Delhivery', 'DL1').status in (200, 204))
    check('same status fixes tracking with a note', staff_update(staff, cod, 'shipped', 'Tracking number corrected', None, 'DL2').status in (200, 204))
    o = alice.one(f'orders?id=eq.{cod}')
    check('... courier kept, tracking replaced', (o['courier'], o['tracking_number']) == ('Delhivery', 'DL2'), o)
    check('shipped -> cancelled refused', code(staff_update(staff, cod, 'cancelled')) == 'INVALID_TRANSITION')
    check('customer cannot cancel a shipped order', code(alice.rpc('cancel_order', {'p_order_id': cod})) == 'INVALID_TRANSITION')
    check('shipped -> delivered', staff_update(staff, cod, 'delivered').status in (200, 204))
    check('... COD becomes paid on delivery', alice.one(f'orders?id=eq.{cod}')['payment_status'] == 'paid')
    check('delivered -> refunded', staff_update(staff, cod, 'refunded', 'Returned: box damaged').status in (200, 204))
    o = alice.one(f'orders?id=eq.{cod}&select=status,payment_status,order_events(status,note,id)')
    check('... refunded/refunded', (o['status'], o['payment_status']) == ('refunded', 'refunded'), o)
    check('customer timeline is exact', timeline(cod) == [('confirmed', None), ('packed', None), ('shipped', None),
                                                          ('shipped', 'Tracking number corrected'), ('delivered', None),
                                                          ('refunded', 'Returned: box damaged')], timeline(cod))
    check('refunded is final', code(staff_update(staff, cod, 'delivered')) == 'INVALID_TRANSITION')

    set_cart(alice, {'c': 1})
    cod2 = place(alice, aa, 'cod').body
    staff_update(staff, cod2, 'packed')
    s0 = stock('c')
    check('staff cancels a packed COD order', staff_update(staff, cod2, 'cancelled').status in (200, 204) and stock('c') == s0 + 1)
    check('... unpaid: default note, no refund line', timeline(cod2)[-1] == ('cancelled', None), timeline(cod2))
    check('cancelled -> confirmed refused', code(staff_update(staff, cod2, 'confirmed')) == 'INVALID_TRANSITION')

    if functions:
        section('lifecycle: Razorpay via signed webhooks')
        d0 = dashboard(staff)
        set_cart(alice, {'c': 1, 'cheap': 2})
        r1 = place(alice, aa, 'razorpay').body
        rzp1, t1 = set_rzp(r1), order(r1)['total_paise']
        check('online order total', t1 == 20000 + 200 + FEE, t1)
        webhook(captured(rzp1, f'pay_{RUN}_r1', t1))
        check('customer cancels her paid order', alice.rpc('cancel_order', {'p_order_id': r1}).status in (200, 204))
        check('... timeline promises the refund', timeline(r1)[-1] == ('cancelled', 'Cancelled by you. ' + REFUND_NOTE), timeline(r1))
        check('... dashboard: needs refund +1', dashboard(staff)['needs_refund'] == d0['needs_refund'] + 1)
        r = webhook(refund_event(f'pay_{RUN}_r1', t1, 1000))
        check('partial refund leaves it for staff', r.body == {'result': 'partial_refund'} and order(r1)['payment_status'] == 'paid', r)
        r = webhook(refund_event(f'pay_{RUN}_r1', t1, t1, with_payment=False))
        check('refund event without the payment entity is not taken as a full refund', r.body == {'result': 'partial_refund'} and order(r1)['payment_status'] == 'paid', r)
        r = webhook(refund_event(f'pay_{RUN}_r1', t1, t1))
        check('full refund -> refunded', r.body == {'result': 'refunded'} and order(r1)['payment_status'] == 'refunded', r)
        check('... timeline says so', timeline(r1)[-1] == ('cancelled', 'Refund issued. Banks usually take 5–7 working days to show it.'), timeline(r1))
        check('... leaves the needs-refund list', dashboard(staff)['needs_refund'] == d0['needs_refund'])
        check('repeated refund event is harmless', webhook(refund_event(f'pay_{RUN}_r1', t1, t1)).body == {'result': 'refunded'}
              and timeline(r1).count(('cancelled', 'Refund issued. Banks usually take 5–7 working days to show it.')) == 1)

        # late payment on an expired order revives it (stock allowing)
        set_cart(alice, {'c': 2})
        r2 = place(alice, aa, 'razorpay').body
        rzp2, s0 = set_rzp(r2), stock('c')
        SVC.patch(f'orders?id=eq.{r2}', {'reserved_until': '2000-01-01T00:00:00Z'})
        SVC.rpc('expire_unpaid_orders')
        check('expired order released 2 units', stock('c') == s0 + 2)
        r = webhook(captured(rzp2, f'pay_{RUN}_r2', order(r2)['total_paise']))
        o = order(r2)
        check('late payment revives the expired order', (o['status'], o['payment_status']) == ('confirmed', 'paid') and stock('c') == s0, (r, o))
        check('... timeline', timeline(r2) == [('pending_payment', None), ('cancelled', 'Payment not received in time'), ('confirmed', 'Payment received')], timeline(r2))

        # late payment on an expired order whose stock is gone -> needs refund
        staff.patch(f'variants?id=eq.{V["last"]}', {'stock': 1})
        set_cart(alice, {'last': 1})
        r3 = place(alice, aa, 'razorpay').body
        rzp3 = set_rzp(r3)
        SVC.patch(f'orders?id=eq.{r3}', {'reserved_until': '2000-01-01T00:00:00Z'})
        SVC.rpc('expire_unpaid_orders')
        set_cart(bob, {'last': 1})
        bob_last = place(bob, addrs['bob'], 'cod').body
        d1 = dashboard(staff)
        webhook(captured(rzp3, f'pay_{RUN}_r3', order(r3)['total_paise']))
        o = order(r3)
        check('late payment without stock: stays cancelled, paid', (o['status'], o['payment_status']) == ('cancelled', 'paid') and stock('last') == 0, o)
        check('... needs refund +1', dashboard(staff)['needs_refund'] == d1['needs_refund'] + 1)
        check('... timeline', timeline(r3)[-1] == ('cancelled', 'Payment received after cancellation. A refund is due.'), timeline(r3))
        bob.rpc('cancel_order', {'p_order_id': bob_last})

        # payment after the customer cancelled is never revived
        set_cart(alice, {'c': 1})
        r4 = place(alice, aa, 'razorpay').body
        rzp4 = set_rzp(r4)
        alice.rpc('cancel_order', {'p_order_id': r4})
        s0 = stock('c')
        webhook(captured(rzp4, f'pay_{RUN}_r4', order(r4)['total_paise']))
        o = order(r4)
        check('payment after a customer cancel: not revived, needs refund', (o['status'], o['payment_status']) == ('cancelled', 'paid') and stock('c') == s0, o)

        # staff cancels a paid, packed order
        set_cart(alice, {'c': 1})
        r5 = place(alice, aa, 'razorpay').body
        webhook(captured(set_rzp(r5), f'pay_{RUN}_r5', order(r5)['total_paise']))
        staff_update(staff, r5, 'packed')
        s0 = stock('c')
        check('staff cancels a paid packed order', staff_update(staff, r5, 'cancelled').status in (200, 204) and stock('c') == s0 + 1)
        check('... note promises the refund', timeline(r5)[-1] == ('cancelled', 'Cancelled by the store. ' + REFUND_NOTE), timeline(r5))
        check('admin cannot confirm an unpaid online order', code(staff_update(staff, place_one(alice, aa), 'confirmed')) == 'INVALID_TRANSITION')

    section('lifecycle: repairs')
    today = time.strftime('%Y-%m-%d', time.gmtime(time.time() + 19800))
    base = {'user_id': alice.uid, 'device_brand': 'Vivo', 'device_model': 'Y20', 'issue': 'battery', 'preferred_date': today,
            'slot': 'evening', 'contact_phone': '+919876543210', 'description': 'drains fast'}
    rep = alice.post('repair_bookings', base)
    check('alice books a repair', rep.status == 201 and rep.body[0]['status'] == 'requested' and rep.body[0]['number'].startswith('RP'), rep)
    rid = rep.body[0]['id']
    REPAIRS.append(rid)
    check('alice cannot quote or confirm her own repair', alice.patch(f'repair_bookings?id=eq.{rid}', {'status': 'completed', 'quote_paise': 0}).body == [])
    r = staff.patch(f'repair_bookings?id=eq.{rid}', {'status': 'confirmed', 'quote_paise': 150000, 'admin_note': 'Battery ₹1,500'})
    check('staff quotes and confirms', r.status == 200 and alice.one(f'repair_bookings?id=eq.{rid}')['quote_paise'] == 150000, r)
    check('alice cancels the confirmed repair', alice.rpc('cancel_repair', {'p_booking_id': rid}).status in (200, 204)
          and alice.one(f'repair_bookings?id=eq.{rid}')['status'] == 'cancelled')
    check('cancel twice -> INVALID_TRANSITION', code(alice.rpc('cancel_repair', {'p_booking_id': rid})) == 'INVALID_TRANSITION')
    rid2 = alice.post('repair_bookings', base).body[0]['id']
    REPAIRS.append(rid2)
    for st in ('confirmed', 'in_progress'):
        staff.patch(f'repair_bookings?id=eq.{rid2}', {'status': st})
    check('in-progress repair cannot be cancelled by the customer', code(alice.rpc('cancel_repair', {'p_booking_id': rid2})) == 'INVALID_TRANSITION')
    for st in ('ready', 'completed'):
        staff.patch(f'repair_bookings?id=eq.{rid2}', {'status': st})
    check('staff completes it', alice.one(f'repair_bookings?id=eq.{rid2}')['status'] == 'completed')


def offers_checks(staff: Actor, alice: Actor, bob: Actor, carol: Actor, dave: Actor, addrs: dict, functions: bool) -> None:
    section('offers: coupons, one-use race, rate limit, discounted payments')
    tag = f'E2E{RUN.upper()}'
    SVC.patch('store_settings?id=eq.true', {'referral_enabled': True})

    def save(actor, body):
        return actor.rpc('admin_save_promotion', {'p': body})

    def checkout(actor, method, coupon):
        r = actor.rpc('place_order', {'p_address_id': addrs[actor.name], 'p_payment_method': method, 'p_coupon_code': coupon})
        if r.status == 200 and isinstance(r.body, str):
            ORDERS.append(r.body)
        return r

    r = save(staff, {'title': 'E2E phone 10%', 'code': tag + 'P', 'kind': 'percent', 'value': 10, 'applies_to': 'items',
                     'per_user_limit': None, 'targets': [{'target_type': 'product', 'target_id': P['phone']}]})
    check('staff create an items coupon', r.status == 200, r)
    r = save(staff, {'title': 'E2E once', 'code': tag + 'ONE', 'kind': 'flat', 'value': 5000, 'usage_limit': 1, 'per_user_limit': None})
    check('staff create a one-use coupon', r.status == 200, r)
    r = save(staff, {'title': 'E2E hidden', 'code': tag + 'H', 'kind': 'flat', 'value': 1000, 'is_public': False})
    check('staff create a hidden coupon', r.status == 200, r)
    r = save(alice, {'title': 'Mine', 'code': tag + 'X', 'kind': 'flat', 'value': 100000})
    check('customers cannot create coupons', code(r) == 'FORBIDDEN', r)
    r = alice.post('promotions', {'title': 'Mine', 'code': tag + 'X', 'kind': 'flat', 'value': 100000})
    check('... not even with a direct insert', r.status in (401, 403), r)
    r = alice.get('promotions?select=code')
    check('customers cannot read promotions (hidden codes stay hidden)', r.status == 200 and r.body == [], r)
    r = ANON.get('promotions?select=code')
    check('anon cannot read promotions', r.status == 401, r)
    r = alice.post('promotion_redemptions', {'order_id': ORDERS[0], 'promotion_id': ORDERS[0], 'discount_paise': 0})
    check('customers cannot write redemptions', r.status in (401, 403), r)
    r = ANON.rpc('available_offers')
    codes = {o['code'] for o in r.body} if r.status == 200 else set()
    check('anon lists public coupons, never hidden ones', tag + 'P' in codes and tag + 'H' not in codes, r)
    for fn in ('quote_order', 'my_referral', 'apply_referral_code', 'admin_save_promotion', 'admin_promotions'):
        check(f'anon cannot call {fn}', denied(ANON.rpc(fn, {'p_code': 'X'} if fn == 'apply_referral_code' else {'p': {}} if fn == 'admin_save_promotion' else {})))

    # 10% of the phone line only: subtotal 69,900 (below free delivery), total 69,900 + fee - 2,000
    set_cart(alice, {'c': 1, 'g12': 1})
    q = alice.rpc('quote_order', {'p_coupon_code': f' {tag.lower()}p '}).body
    check('quote: 10% of the targeted line', isinstance(q, dict) and (q['subtotal_paise'], q['delivery_fee_paise'], q['discount_paise'], q['total_paise'],
          q['promotion']['code'], q['coupon_error']) == (69900, FEE, 2000, 69900 + FEE - 2000, tag + 'P', None), q)
    r = checkout(alice, 'cod', tag.lower() + 'p')
    o = order(r.body) if r.status == 200 else {}
    check('order charges exactly the quote', o and (o['subtotal_paise'], o['delivery_fee_paise'], o['discount_paise'], o['total_paise'], o['coupon_code'])
          == (69900, FEE, 2000, 69900 + FEE - 2000, tag + 'P'), r if not o else o)
    check('... the discount sits on the phone line', o and {i['variant_id']: i['discount_paise'] for i in o['order_items']} == {V['c']: 2000, V['g12']: 0}, o)
    if o:
        alice.rpc('cancel_order', {'p_order_id': o['id']})
    set_cart(alice, {'c': 1})
    r = alice.rpc('place_order', {'p_address_id': addrs['alice'], 'p_payment_method': 'cod', 'p_discount_paise': 999999})
    check('a client-sent discount is not a parameter', r.status == 404 and r.body.get('code') == 'PGRST202', r)
    r = checkout(alice, 'cod', 'NOSUCHCODE')
    check('place_order refuses an unknown code', code(r) == 'COUPON_NOT_FOUND', r)
    set_cart(alice, {})

    # one use left, four parallel checkouts of different lines: only the promotion row lock serializes them
    racers = [alice, bob, carol, dave]
    for c, line in zip(racers, ('c', 'a', 'b', 'race')):
        set_cart(c, {line: 1})
    barrier = threading.Barrier(len(racers))

    def go(c):
        barrier.wait()
        return checkout(c, 'cod', tag + 'ONE')

    with ThreadPoolExecutor(len(racers)) as ex:
        results = list(ex.map(go, racers))
    wins = [(c, r) for c, r in zip(racers, results) if r.status == 200]
    check('4 parallel checkouts with a one-use code: exactly one gets it',
          len(wins) == 1 and all(code(r) == 'COUPON_USED_UP' for r in results if r.status != 200), results)
    for c in racers:
        set_cart(c, {})
    for c, r in wins:
        c.rpc('cancel_order', {'p_order_id': r.body})
    set_cart(bob, {'c': 1})
    q = bob.rpc('quote_order', {'p_coupon_code': tag + 'ONE'}).body
    check('... cancelling that order gives the use back', isinstance(q, dict) and q['discount_paise'] == 5000 and q['coupon_error'] is None, q)
    set_cart(bob, {})

    if functions:
        set_cart(bob, {'c': 1})
        r = checkout(bob, 'razorpay', tag + 'P')
        if check('discounted Razorpay order placed', r.status == 200, r):
            oid, total = r.body, 20000 - 2000 + FEE
            rzp = set_rzp(oid)
            p = bob.fn('create-payment', {'order_id': oid})
            check('create-payment asks Razorpay for the discounted total', p.status == 200 and p.body['amount'] == total, p)
            w = webhook(captured(rzp, f'pay_{RUN}_off1', 20000 + FEE))
            check('a payment of the undiscounted amount is refused', w.body == {'result': 'amount_mismatch'} and order(oid)['payment_status'] == 'pending', w)
            w = webhook(captured(rzp, f'pay_{RUN}_off2', total))
            o = order(oid)
            check('the discounted amount pays it', w.body == {'result': 'paid'} and (o['status'], o['payment_status']) == ('confirmed', 'paid'), (w, o))
            staff_update(staff, oid, 'cancelled', 'e2e')

    # wrong guesses are rate limited (failed lookups count; 10 per 10 minutes)
    set_cart(dave, {'c': 1})
    misses = [dave.rpc('quote_order', {'p_coupon_code': f'GUESS{n}'}).body.get('coupon_error') for n in range(10)]
    q = dave.rpc('quote_order', {'p_coupon_code': tag + 'P'}).body
    check('10 wrong guesses, then even a good code is refused', misses == ['COUPON_NOT_FOUND'] * 10 and q.get('coupon_error') == 'COUPON_RATE_LIMIT'
          and q['discount_paise'] == 0, (misses, q))
    set_cart(dave, {})

    r = carol.rpc('my_referral')  # carol deletes her account later: her referral code must not block it
    check('my_referral gives a code', r.status == 200 and isinstance(r.body.get('code'), str) and 6 <= len(r.body['code']) <= 10, r)
    r = staff.rpc('admin_promotions')
    mine = {p['code']: p for p in r.body if (p['code'] or '').startswith(tag)} if r.status == 200 else {}
    check('admin_promotions counts uses over orders that are not cancelled', mine.get(tag + 'P', {}).get('uses') == 0
          and mine.get(tag + 'ONE', {}).get('uses') == 0, mine)


def caps_checks(staff: Actor, alice: Actor, aa: str) -> None:
    section('abuse caps')
    for o in SVC.get(f'orders?select=id&user_id=eq.{alice.uid}&status=eq.pending_payment').body:
        alice.rpc('cancel_order', {'p_order_id': o['id']})
    tries = []
    for _ in range(3):
        set_cart(alice, {'cheap': 1})
        tries.append(place(alice, aa, 'razorpay'))
    check('2 unpaid online orders allowed, a 3rd -> PENDING_LIMIT', [t.status for t in tries[:2]] == [200, 200]
          and code(tries[2]) == 'PENDING_LIMIT', tries)
    r = place(alice, aa, 'cod')
    check('... COD is not capped', r.status == 200, r)
    alice.rpc('cancel_order', {'p_order_id': r.body})
    SVC.patch(f'orders?id=eq.{tries[0].body}', {'reserved_until': '2000-01-01T00:00:00Z'})
    set_cart(alice, {'cheap': 1})
    r = place(alice, aa, 'razorpay')
    check('... an expired hold no longer counts', r.status == 200, r)
    for oid in (tries[0].body, tries[1].body, r.body):
        alice.rpc('cancel_order', {'p_order_id': oid})

    lines = [f'l{n:02}' for n in range(1, 22)]
    set_cart(alice, {k: 1 for k in lines[:11]})
    check('11 lines in one order -> CART_LIMIT', code(place(alice, aa, 'cod')) == 'CART_LIMIT')
    set_cart(alice, {k: 1 for k in lines[:10]})
    r = place(alice, aa, 'cod')
    check('10 lines place', r.status == 200, r)
    alice.rpc('cancel_order', {'p_order_id': r.body})
    set_cart(alice, {k: 1 for k in lines[:20]})
    r = alice.post('cart_items', {'user_id': alice.uid, 'variant_id': V['l21'], 'qty': 1})
    check('a 21st cart line -> CART_LIMIT', code(r) == 'CART_LIMIT', r)
    r = alice.post('cart_items', {'user_id': alice.uid, 'variant_id': V['l01'], 'qty': 3}, prefer='return=representation,resolution=merge-duplicates')
    check('upserting an existing line at the cap still works (how the app adds to cart)', r.status in (200, 201) and r.body[0]['qty'] == 3, r)
    set_cart(alice, {})

    today = time.strftime('%Y-%m-%d', time.gmtime(time.time() + 19800))
    base = {'user_id': alice.uid, 'device_brand': 'Nokia', 'device_model': '3310', 'issue': 'other', 'preferred_date': today,
            'slot': 'afternoon', 'contact_phone': '+919876543210'}
    open_ = [alice.post('repair_bookings', base) for _ in range(3)]
    REPAIRS.extend(x.body[0]['id'] for x in open_ if x.status == 201)
    r = alice.post('repair_bookings', base)
    check('3 open repairs allowed, a 4th -> REPAIR_LIMIT', [x.status for x in open_] == [201] * 3 and code(r) == 'REPAIR_LIMIT', r)
    r = staff.post('repair_bookings', base)
    check('staff book a walk-in past the cap', r.status == 201, r)
    if r.status == 201:
        REPAIRS.append(r.body[0]['id'])
    for rid in REPAIRS[-4:]:
        alice.rpc('cancel_repair', {'p_booking_id': rid})
    r = alice.post('repair_bookings', base)
    check('cancelled bookings free the slots', r.status == 201, r)
    if r.status == 201:
        REPAIRS.append(r.body[0]['id'])


def input_checks(staff: Actor, alice: Actor, addr: str) -> None:
    section('hostile input (direct API calls, not the app)')
    sqlish = "Robert'); drop table public.orders; -- ' or '1'='1 $$; select pg_sleep(5); $$ %_\\ <script>"
    prof = f'profiles?id=eq.{alice.uid}'
    for name in ('श्याम कुमार', 'José Ñúñez', sqlish[:80]):
        r = alice.patch(prof, {'full_name': name})
        check(f'name {name[:24]!r} is stored verbatim', r.status == 200 and r.body[0]['full_name'] == name, r)
    for label, name in {'10,000 characters': 'a' * 10000, 'emoji only': '😀😀😀', 'zero-width space': 'Ali​ce',
                        'bidi override': 'Ali‮ecila', 'BOM': '﻿Alice', 'newline': 'Ali\nce', 'control char': 'Ali\u0007ce',
                        'NUL': 'Ali\u0000ce', 'blank': '   ', 'digits only': '12345', 'a number, not text': 42}.items():
        r = alice.patch(prof, {'full_name': name})
        check(f'profile name refused: {label}', r.status == 400, r)
    for label, ph in {'spaces': '+91 98765 43210', '11 digits': '+9198765432101', 'no +91': '9876543210', 'starts with 5': '+915876543210',
                      'Devanagari digits': '+९१९८७६५४३२१०', 'fullwidth digits': '+９１９８７６５４３２１０', 'trailing newline': '+919876543210\n',
                      'SQL': "+919876543210' or '1'='1"}.items():
        r = alice.patch(prof, {'phone': ph})
        check(f'phone refused: {label}', r.status == 400, r)
    alice.patch(prof, {'full_name': 'Alice E2E', 'phone': '+919812345678'})

    base = {'user_id': alice.uid, 'name': 'Alice', 'phone': '+919876543210', 'line1': '1 Rajeev Complex', 'city': 'Waidhan',
            'state': 'Madhya Pradesh', 'pincode': '486886'}
    for label, extra in {'7-digit pincode': {'pincode': '4868860'}, 'pincode starting 0': {'pincode': '086886'},
                         'letter in pincode': {'pincode': '48688a'}, 'fullwidth pincode': {'pincode': '４８６８８６'},
                         'spaced pincode': {'pincode': ' 486886'}, 'emoji-only city': {'city': '🏙️🏙️'},
                         '10,000-char line1': {'line1': 'x' * 10000}, 'bidi override in line1': {'line1': '1 MG‮ Road'},
                         'zero-width name': {'name': '​​​'}, 'unknown label': {'label': 'office'},
                         'phone with spaces': {'phone': '+91 98765 43210'}, 'whitespace-only landmark': {'landmark': '   '}}.items():
        r = alice.post('addresses', {**base, **extra})
        check(f'address refused: {label}', r.status == 400, r)
    r = alice.post('addresses', {**base, 'line1': sqlish[:120], 'landmark': 'Near "Shiv" mandir & 1 < 2'})
    check('SQL-ish address text is stored verbatim', r.status == 201 and r.body[0]['line1'] == sqlish[:120], r)
    if r.status == 201:
        alice.delete(f'addresses?id=eq.{r.body[0]["id"]}')

    today = time.strftime('%Y-%m-%d', time.gmtime(time.time() + 19800))
    rep = {'user_id': alice.uid, 'device_brand': 'Nokia', 'device_model': '3310', 'issue': 'other', 'preferred_date': today,
           'slot': 'morning', 'contact_phone': '+919876543210'}
    for label, extra in {'501-char description': {'description': 'd' * 501}, 'bidi override in description': {'description': 'ok‮ko'},
                         'phone with spaces': {'contact_phone': '+91 98765 43210'}, 'unknown issue': {'issue': 'hacked'},
                         'unknown slot': {'slot': 'midnight'}, 'blank model': {'device_model': ' '}, 'malformed date': {'preferred_date': '2026-13-45'}}.items():
        r = alice.post('repair_bookings', {**rep, **extra})
        check(f'repair refused: {label}', r.status == 400, r)
    r = alice.post('repair_bookings', {**rep, 'description': 'Screen flickers.\nAlso: ' + sqlish})
    check('digits-only model and a multi-line, SQL-ish description book fine', r.status == 201 and r.body[0]['description'].endswith(sqlish), r)
    if r.status == 201:
        REPAIRS.append(r.body[0]['id'])
        alice.rpc('cancel_repair', {'p_booking_id': r.body[0]['id']})

    for label, body in {'Cyrillic look-alike SKU': {'sku': f'SАM-{RUN}'}, 'SKU with a space': {'sku': f'SAM {RUN}'},
                        '61-char SKU': {'sku': 'S' * 61}, 'negative price': {'price_paise': -1}, 'zero price': {'price_paise': 0},
                        'price past int': {'price_paise': 2147483648}, 'decimal price': {'price_paise': 99.5},
                        'MRP under price': {'mrp_paise': 1}, 'negative stock': {'stock': -1}, 'stock over 1,000,000': {'stock': 1000001},
                        'colour not #RRGGBB': {'attributes': {'color_hex': 'red'}}, 'oversized attributes': {'attributes': {'x': 'y' * 2000}},
                        'zero-width variant name': {'name': '8 GB​'}}.items():
        r = staff.patch(f'variants?id=eq.{V["c"]}', body)
        check(f'staff variant edit refused: {label}', r.status == 400, r)
    for label, body in {'Cyrillic look-alike slug': {'slug': f'e2e-{RUN}-рhone'}, '161-char slug': {'slug': 'a' * 161},
                        'upper-case slug': {'slug': f'E2E-{RUN}'}, 'GST over 28': {'gst_rate': 28.01}, 'negative GST': {'gst_rate': -1},
                        'bidi override in name': {'name': 'Galaxy‮ S25'}, '5,001-char description': {'description': 'x' * 5001},
                        'specs not an array': {'specs': {'Display': '6.2'}}}.items():
        r = staff.patch(f'products?id=eq.{P["acc"]}', body)
        check(f'staff product edit refused: {label}', r.status == 400, r)
    desc = 'Line one.\nLine two: ' + sqlish
    r = staff.patch(f'products?id=eq.{P["acc"]}', {'description': desc})
    check('multi-line, SQL-ish product description stored verbatim', r.status == 200 and r.body[0]['description'] == desc, r)
    r = staff.post('product_images', {'product_id': P['acc'], 'path': '../../other/x.png'})
    check('product image key climbing out of its folder refused', r.status == 400, r)
    for label, body in {'negative delivery fee': {'delivery_fee_paise': -1}, 'COD limit past int': {'cod_max_paise': 2147483648},
                        'newline in hours': {'store_hours': '10 am\n9 pm'}, '301-char address': {'store_address': 'a' * 301},
                        'photo key outside store/': {'store_photos': ['../x.png']}, 'shop phone with spaces': {'store_phone': '+91 98765 43210'},
                        'javascript: maps link': {'store_maps_url': 'javascript:alert(1)'}, 'latitude 91': {'store_lat': 91, 'store_lng': 0},
                        'half a pin': {'store_lat': 24.0, 'store_lng': None}}.items():
        r = staff.patch('store_settings?id=eq.true', body)
        check(f'staff settings edit refused: {label}', r.status == 400, r)

    set_cart(alice, {'cheap': 1})
    oid = place(alice, addr, 'cod').body
    for label, args in {'501-char note': {'p_note': 'n' * 501}, 'control char in courier': {'p_courier': 'Delhi\u0007very'},
                        '61-char tracking number': {'p_tracking_number': 't' * 61}}.items():
        r = staff.rpc('admin_update_order', {'p_order_id': oid, 'p_status': 'confirmed', 'p_note': None, 'p_courier': None,
                                             'p_tracking_number': None, **args})
        check(f'order update refused: {label}', r.status == 400, r)
    check('... and the timeline is untouched', timeline(oid) == [('confirmed', None)], timeline(oid))
    alice.rpc('cancel_order', {'p_order_id': oid})
    for label, (fn, args) in {'payment method "bitcoin"': ('place_order', {'p_address_id': addr, 'p_payment_method': 'bitcoin'}),
                              'address id not a uuid': ('place_order', {'p_address_id': "'; drop table orders; --", 'p_payment_method': 'cod'}),
                              'order id not a uuid': ('cancel_order', {'p_order_id': '1 or 1=1'}),
                              'extra argument': ('cancel_order', {'p_order_id': oid, 'p_user_id': staff.uid})}.items():
        r = alice.rpc(fn, args)
        check(f'RPC refused cleanly: {label}', r.status in (400, 404), r)


def place_one(actor: Actor, addr: str) -> str:
    set_cart(actor, {'cheap': 1})
    return place(actor, addr, 'razorpay').body


def delete_account_checks(carol: Actor, addr: str) -> None:
    section('delete-account')
    set_cart(carol, {'cheap': 1})
    oid = place(carol, addr, 'cod').body
    carol.post('wishlist', {'user_id': carol.uid, 'product_id': P['phone']})
    set_cart(carol, {'c': 1})
    r = carol.fn('delete-account')
    check('open order -> 409 ACTIVE_ORDERS', r.status == 409 and code(r) == 'ACTIVE_ORDERS', r)
    carol.rpc('cancel_order', {'p_order_id': oid})
    today = time.strftime('%Y-%m-%d', time.gmtime(time.time() + 19800))
    rid = carol.post('repair_bookings', {'user_id': carol.uid, 'device_brand': 'Oppo', 'device_model': 'A5', 'issue': 'other',
                                         'preferred_date': today, 'slot': 'morning', 'contact_phone': '+919876543210'}).body[0]['id']
    REPAIRS.append(rid)
    r = carol.fn('delete-account')
    check('open repair -> 409 ACTIVE_ORDERS', r.status == 409, r)
    carol.rpc('cancel_repair', {'p_booking_id': rid})
    r = carol.fn('delete-account')
    check('nothing open -> 204', r.status == 204, r)
    check('auth user gone', http('GET', f'/auth/v1/admin/users/{carol.uid}', key=SECRET).status == 404)
    for t, col in (('profiles', 'id'), ('addresses', 'user_id'), ('cart_items', 'user_id'), ('wishlist', 'user_id')):
        check(f'{t} deleted', SVC.get(f'{t}?{col}=eq.{carol.uid}').body == [])
    o = SVC.one(f'orders?id=eq.{oid}&select=user_id,address,total_paise')
    check('order kept for tax records with user_id null', o['user_id'] is None and o['address']['name'] == 'Carol', o)
    check('repair kept with user_id null', SVC.one(f'repair_bookings?id=eq.{rid}')['user_id'] is None)
    check("her still-unexpired token sees nothing", carol.get('orders?select=id').body == [])


def auth_checks(alice: Actor, bob: Actor) -> None:
    section('auth')
    attacker = f'e2e-{RUN}-victim@example.com'
    r = http('POST', '/auth/v1/signup', {'email': attacker, 'password': 'Attacker-Pass-123'})
    uid = (r.body.get('user') or r.body).get('id') if isinstance(r.body, dict) else None
    if uid:
        CREATED_USERS.append(uid)
    check('password sign-up for someone else\'s email gives no session (passwordless; pre-hijack)',
          not (isinstance(r.body, dict) and r.body.get('access_token')), f'{r.status}: got a session; restart the stack so the auth hook and confirmations load')
    r = http('POST', '/auth/v1/token?grant_type=password', {'email': attacker, 'password': 'Attacker-Pass-123'})
    check('... and no password sign-in afterwards', r.status != 200, r.status)
    phone = '+9196' + str(secrets.randbelow(10**8)).zfill(8)
    r = http('POST', '/auth/v1/signup', {'phone': phone, 'password': 'Attacker-Pass-123'})
    uid = (r.body.get('user') or r.body).get('id') if isinstance(r.body, dict) else None
    if uid:
        CREATED_USERS.append(uid)
    check("password sign-up for someone else's phone gives no session", not (isinstance(r.body, dict) and r.body.get('access_token')), r.status)
    first = http('POST', '/auth/v1/otp', {'phone': '+919999999999'})
    second = http('POST', '/auth/v1/otp', {'phone': '+919999999999'})
    check('OTP resend within 60 s -> 429 (sms max_frequency)', first.status in (200, 429) and second.status == 429, (first, second))
    r = http('POST', '/auth/v1/verify', {'type': 'sms', 'phone': '+919999999999', 'token': '000000'})
    check('wrong OTP refused', r.status in (400, 403), r)
    # PostgREST must reject forged/tampered tokens
    now = int(time.time())
    claims = {'sub': alice.uid, 'role': 'service_role', 'aud': 'authenticated', 'iat': now, 'exp': now + 600}
    for label, tok in (('role claim tampered to service_role', tamper(alice.token, role='service_role')),
                       ('sub tampered to bob', tamper(alice.token, sub=bob.uid)),
                       ('alg none', jwt(claims, None, 'none')),
                       ('HS256 with a wrong secret', jwt(claims, 'wrong-secret-wrong-secret-wrong-secret!')),
                       ('expired', jwt({**claims, 'role': 'authenticated', 'exp': now - 60}, ENV['JWT_SECRET']))):
        r = http('GET', '/rest/v1/payment_events?select=id&limit=1', token=tok)
        check(f'PostgREST rejects a forged JWT: {label}', r.status == 401, r)


def audit_numbers() -> None:
    section('numbers audit (every order this run created)')
    bad = []
    for oid in ORDERS:
        o = order(oid)
        items = o['order_items']
        sub = sum(i['unit_price_paise'] * i['qty'] for i in items)
        disc = o['discount_paise']
        fee_ok = o['delivery_fee_paise'] == (0 if o['subtotal_paise'] - disc >= FREE_MIN else FEE)
        gst_ok = all(float(i['gst_rate']) == GST[next(k for k, v in P.items() if v == i['product_id'])] for i in items)
        if not (items and sub == o['subtotal_paise'] and o['total_paise'] == o['subtotal_paise'] + o['delivery_fee_paise'] - disc and fee_ok and gst_ok
                and sum(i['discount_paise'] for i in items) == disc and all(1 <= i['qty'] <= 5 for i in items) and o['order_events']):
            bad.append((o['number'], sub, o['subtotal_paise'], o['delivery_fee_paise'], o['total_paise']))
    check(f'{len(ORDERS)} orders: subtotal = Σ unit×qty, total = subtotal + fee − discount = Σ line discounts, fee rule, GST, timeline', ORDERS and not bad, bad)
    r = SVC.get(f'variants?select=sku,stock&product_id=in.({",".join(P.values())})&stock=lt.0')
    check('no variant stock below zero', r.body == [], r)


def cleanup(staff, settings, paths) -> None:
    section('cleanup')
    if ORDERS:
        SVC.delete(f'orders?id=in.({",".join(ORDERS)})')
    SVC.delete(f'promotions?code=like.E2E{RUN.upper()}*')
    for uid in CREATED_USERS:
        SVC.delete(f'repair_bookings?user_id=eq.{uid}')
        SVC.delete(f'orders?user_id=eq.{uid}')
        http('DELETE', f'/auth/v1/admin/users/{uid}', key=SECRET)
    if REPAIRS:
        SVC.delete(f'repair_bookings?id=in.({",".join(REPAIRS)})')
    SVC.delete(f'payment_events?razorpay_event_id=like.evt_e2e_{RUN}*')
    if P:
        SVC.delete(f'products?id=in.({",".join(P.values())})')
    SVC.delete(f'brands?slug=eq.e2e-{RUN}')
    SVC.delete(f'categories?slug=eq.e2e-{RUN}')
    if paths:
        staff.req('DELETE', '/storage/v1/object/product-images', {'prefixes': paths})
    if settings:
        SVC.patch('store_settings?id=eq.true', {k: v for k, v in settings.items() if k not in ('id', 'updated_at')})
    print('removed e2e data, restored store_settings')


def main() -> None:
    print(f'run e2e-{RUN} against {API}')
    staff = sign_in(DEV['DEV_ADMIN_EMAIL'], DEV['DEV_ADMIN_PASSWORD'], 'staff')
    settings = SVC.one('store_settings?select=*')
    paths = []
    try:
        SVC.patch('store_settings?id=eq.true', {'delivery_fee_paise': FEE, 'free_delivery_min_paise': FREE_MIN, 'cod_enabled': True, 'cod_max_paise': 2500000})
        setup_catalog(staff)
        alice, bob, carol, dave = (new_customer(n) for n in ('alice', 'bob', 'carol', 'dave'))
        addrs = {c.name: address(c) for c in (alice, bob, carol, dave)}
        set_cart(alice, {'cheap': 1})
        a_order = place(alice, addrs['alice'], 'cod').body
        set_cart(bob, {'cheap': 1})
        b_order = place(bob, addrs['bob'], 'cod').body
        set_cart(bob, {'cheap': 1, 'c': 1})
        bob.post('wishlist', {'user_id': bob.uid, 'product_id': P['phone']})
        set_cart(alice, {'c': 1})
        alice.post('wishlist', {'user_id': alice.uid, 'product_id': P['phone']})

        anon_checks(a_order)
        customer_checks(alice, bob, staff, addrs['alice'], addrs['bob'], b_order, a_order)
        staff_checks(staff, alice)
        paths = storage_checks(staff, alice)
        money_checks(staff, alice, bob, carol, dave, addrs)
        functions = function_checks(staff, alice, bob, addrs)
        lifecycle(staff, alice, bob, addrs, functions)
        offers_checks(staff, alice, bob, carol, dave, addrs, functions)
        caps_checks(staff, alice, addrs['alice'])
        input_checks(staff, alice, addrs['alice'])
        if functions:
            delete_account_checks(carol, addrs['carol'])
        auth_checks(alice, bob)
        audit_numbers()
    except Exception as e:  # a crashed section is a failure, but cleanup still runs
        import traceback
        traceback.print_exc()
        check('suite ran to the end', False, repr(e))
    finally:
        cleanup(staff, settings, paths)
    print(f'\n{len(FAILS)} failed' if FAILS else '\nall checks passed')
    sys.exit(1 if FAILS else 0)


if __name__ == '__main__':
    main()
