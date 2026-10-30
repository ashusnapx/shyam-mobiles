// Share links, /open parsing (as go_router sees platform deep links) and the pending referral, with fakes.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/deep_links.dart';
import 'package:shyam_mobiles/core/links.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../features/offers/fakes.dart';

const referral = Referral(
  enabled: true,
  code: 'ABCD1234',
  friendPaise: 20000,
  rewardPaise: 20000,
  minOrderPaise: 199900,
  canEnterCode: true,
);

void main() {
  group('share links', () {
    test('product, offer and referral links on LINK_HOST', () {
      expect(shareLink(product: 'samsung-galaxy-s25', code: 'ABCD1234', host: 'shop.in').toString(),
          'https://shop.in/open?p=samsung-galaxy-s25&ref=ABCD1234');
      expect(shareLink(offer: '11111111-1111-1111-1111-111111111111', host: 'shop.in').toString(),
          'https://shop.in/open?o=11111111-1111-1111-1111-111111111111');
      expect(shareLink(code: 'ABCD1234', host: 'shop.in').toString(), 'https://shop.in/open?ref=ABCD1234');
      expect(shareLink(product: 'x', host: ''), isNull);
    });

    test('share text: what, the code and its worth, then the link (or how to get the app)', () {
      final link = shareLink(product: 's25', code: 'ABCD1234', host: 'shop.in');
      expect(shareText('Samsung Galaxy S25 · ₹74,999 at Shyam Mobiles', link: link, referral: referral),
          'Samsung Galaxy S25 · ₹74,999 at Shyam Mobiles\n'
          'Use my code ABCD1234 for ₹200 off your first order of ₹1,999 or more.\n'
          'https://shop.in/open?p=s25&ref=ABCD1234');
      expect(shareText('Samsung Galaxy S25 at Shyam Mobiles'),
          'Samsung Galaxy S25 at Shyam Mobiles\nGet the Shyam Mobiles app on Google Play.');
    });

    test('the welcome message', () {
      final welcome = Offer(id: 'w', title: 'Welcome', code: 'FRIENDX', kind: OfferKind.flat, value: 20000,
          minSubtotalPaise: 199900, startsAt: DateTime(2026));
      expect(friendCodeMessage(welcome), 'Your friend’s code is in: ₹200 off your first order of ₹1,999 or more');
    });
  });

  group('openLink', () {
    OpenLink? open(String s) => openLink(Uri.parse(s));

    test('App Link, custom scheme and the replayed install referrer', () {
      expect(open('https://shop.in/open?p=samsung-galaxy-s25&ref=abcd1234'), (to: '/product/samsung-galaxy-s25', code: 'ABCD1234'));
      expect(open('shyammobiles://open?o=11111111-1111-1111-1111-111111111111'),
          (to: '/offers/11111111-1111-1111-1111-111111111111', code: null));
      expect(openLink(Uri(path: '/open', query: 'p=s25&ref=ABCD1234')), (to: '/product/s25', code: 'ABCD1234'));
      expect(open('shyammobiles://open?ref=ABCD1234'), (to: '/', code: 'ABCD1234'));
      expect(open('shyammobiles://open'), (to: '/', code: null));
    });

    test('anything else is not a link; junk values are dropped', () {
      expect(open('/product/s25'), isNull);
      expect(open('https://shop.in/privacy'), isNull);
      expect(open('shyammobiles://pay?p=s25'), isNull);
      expect(openLink(Uri(path: '/open', query: 'utm_source=google-play&utm_medium=organic')), (to: '/', code: null));
      expect(open('https://shop.in/open?p=../admin&ref=x;drop'), (to: '/', code: null));
      expect(open('https://shop.in/open?o=not-an-id&ref=TOOLONGCODE123'), (to: '/', code: null));
    });

    testWidgets('a deep link from Android reaches the redirect with its scheme and host', (tester) async {
      final seen = <String>[];
      final router = GoRouter(
        redirect: (_, state) => openLink(state.uri)?.to,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('Home')),
          GoRoute(path: '/product/:slug', builder: (_, s) => Text('Product ${s.pathParameters['slug']}')),
        ],
      );
      router.routerDelegate.addListener(() => seen.add(router.state.uri.toString()));
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      // what FlutterActivity sends for an intent's data (the full URI)
      for (final uri in ['shyammobiles://open?p=s25&ref=ABCD1234', 'https://shop.in/open?p=pixel-9a']) {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': uri, 'state': null})),
          (_) {},
        );
        await tester.pumpAndSettle();
      }
      expect(seen, containsAllInOrder(['/product/s25', '/product/pixel-9a']));
      expect(find.text('Product pixel-9a'), findsOneWidget);
    });
  });

  group('pending referral', () {
    late FakeOffersApi api;

    Future<ProviderContainer> start({String? user = 'u1', Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(overrides: [
        currentUserIdProvider.overrideWithValue(user),
        offersApiProvider.overrideWithValue(api),
      ]);
      addTearDown(c.dispose);
      c.read(pendingReferralProvider);
      await pumpEventQueue();
      return c;
    }

    Future<String?> kept() async => (await SharedPreferences.getInstance()).getString('pending_referral');

    setUp(() => api = FakeOffersApi(referral: referral));

    test('a kept code is applied once someone is signed in, then forgotten', () async {
      await start(prefs: {'pending_referral': 'ABCD1234'});
      expect(api.calls, ['referral ABCD1234']);
      expect(await kept(), isNull);
    });

    test('signed out: kept for later, nothing called', () async {
      final c = await start(user: null);
      await c.read(pendingReferralProvider.notifier).remember('ABCD1234');
      expect(api.calls, isEmpty);
      expect(await kept(), 'ABCD1234');
    });

    test('already has a referrer or an order: dropped without trying', () async {
      api.referral = const Referral(enabled: true, code: 'MINE0001', friendPaise: 0, rewardPaise: 0, minOrderPaise: 0);
      await start(prefs: {'pending_referral': 'ABCD1234'});
      expect(api.calls, isEmpty);
      expect(await kept(), isNull);
    });

    test('a REFERRAL_* refusal drops it quietly; a network failure keeps it for next time', () async {
      api.referralError = const PostgrestException(message: 'REFERRAL_SELF');
      await start(prefs: {'pending_referral': 'ABCD1234'});
      expect(api.calls, ['referral ABCD1234']);
      expect(await kept(), isNull);

      api
        ..calls.clear()
        ..referralError = Exception('offline');
      final c = await start(prefs: {'pending_referral': 'ABCD1234'});
      expect(api.calls, ['referral ABCD1234']);
      expect(await kept(), 'ABCD1234');
      await pumpEventQueue();
      expect(api.calls, hasLength(1)); // no retry loop
      await c.read(pendingReferralProvider.notifier).apply(); // the next sign-in or launch tries again
      expect(api.calls, hasLength(2));
    });
  });
}
