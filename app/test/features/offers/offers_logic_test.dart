import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/errors.dart';
import 'package:shyam_mobiles/core/input.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/offers_admin.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_offers_screen.dart' show targetsSummary;
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:shyam_mobiles/features/offers/widgets/offer_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

String _typed(List<TextInputFormatter> formatters, String text) => formatters
    .fold(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
        (v, f) => f.formatEditUpdate(TextEditingValue.empty, v))
    .text;

void main() {
  test('every coupon and referral refusal has its own plain copy', () {
    const codes = [
      'COUPON_NOT_FOUND', 'COUPON_NOT_STARTED', 'COUPON_EXPIRED', 'COUPON_USED_UP', 'COUPON_LIMIT_REACHED',
      'COUPON_MIN_ORDER', 'COUPON_NOT_APPLICABLE', 'COUPON_FIRST_ORDER', 'COUPON_ONLINE_ONLY', 'COUPON_RATE_LIMIT',
      'REFERRAL_OFF', 'REFERRAL_INVALID', 'REFERRAL_SELF', 'REFERRAL_USED', 'REFERRAL_TOO_LATE',
    ];
    final copy = {for (final c in codes) c: friendlyError(PostgrestException(message: c, code: 'P0001'))};
    expect(copy.values.toSet(), hasLength(codes.length), reason: 'no two codes share a message');
    expect(copy.values, everyElement(isNot(fallbackError)));
    expect(copy.values.where((m) => m.contains('COUPON') || m.contains('_')), isEmpty);
    // place_order's detail names the minimum; quote_order's coupon_error doesn't
    expect(friendlyError(const PostgrestException(message: 'COUPON_MIN_ORDER', code: 'P0001', details: '199900')),
        contains('₹1,999'));
    expect(couponError('COUPON_MIN_ORDER', minPaise: 50000), contains('₹500'));
    expect(couponError('COUPON_SOMETHING_NEW'), 'That code can’t be used on this order.');
    // staff: admin_save_promotion names the broken rule
    expect(friendlyError(const PostgrestException(message: 'INVALID_PROMOTION', code: 'P0001', details: 'promotions_window_check')),
        'The end has to be after the start.');
    expect(friendlyError(const PostgrestException(message: 'INVALID_PROMOTION', code: 'P0001', details: 'something new')),
        contains('Check the amount, dates and products'));
    expect(friendlyError(const PostgrestException(message: 'CODE_TAKEN', code: 'P0001')), contains('Generate'));
  });

  test('coupon codes: capitals and digits only, any script’s digits, at most 20', () {
    expect(_typed(couponCodeInput, 'diwali 10'), 'DIWALI10');
    expect(_typed(couponCodeInput, 'ʙɪɢ-sale_२०२६!'), 'SALE2026');
    expect(_typed(couponCodeInput, 'a' * 30), 'A' * 20);
    expect(validateCode('ABC'), 'Codes are 4 to 20 letters and numbers.');
    expect(validateCode('DIWALI10'), isNull);
    expect(validateCode(''), 'Enter a code.');
    expect(validateCode('FRIEND1', min: 6, max: 10), isNull);
    expect(validateCode('FRIENDCODE1', min: 6, max: 10), isNotNull);
  });

  test('banners open only real app routes', () {
    for (final ok in ['/offers', '/offers/${diwali.id}', '/search', '/search?category=smartphones', '/product/galaxy-s25', '/repairs', '/repairs/new']) {
      expect(isBannerLink(ok), isTrue, reason: ok);
    }
    for (final bad in ['https://evil.example', '//evil.example', '/offersX', '/admin', '/product/', '/product/A B', 'intent://x', '/search#x', '']) {
      expect(isBannerLink(bad), isFalse, reason: bad);
    }
  });

  test('time left reads naturally and never goes negative', () {
    final now = DateTime(2026, 10, 30, 12);
    expect(timeLeft(null, now: now), isNull);
    expect(timeLeft(now.add(const Duration(seconds: 20)), now: now), 'Ends in 1 min');
    expect(timeLeft(now.add(const Duration(minutes: 45)), now: now), 'Ends in 45 min');
    expect(timeLeft(now.add(const Duration(hours: 5, minutes: 10)), now: now), 'Ends in 5 h');
    expect(timeLeft(now.add(const Duration(days: 1)), now: now), 'Ends in 1 day');
    expect(timeLeft(now.add(const Duration(days: 3)), now: now), 'Ends in 3 days');
    expect(timeLeft(DateTime(2026, 11, 20), now: now), 'Till 20 Nov 2026');
    expect(timeLeft(now.subtract(const Duration(minutes: 1)), now: now), 'Ended');
  });

  test('offer headline and terms come from the offer as set, not from a computed saving', () {
    expect(offerHeadline(diwali), '₹500 off');
    expect(offerHeadline(festiveSale), '10% off');
    expect(valueHeadline(OfferKind.freeDelivery, 0), 'Free delivery');
    expect(offerTerms(diwali), ['When the offer’s items come to ₹9,999 or more', 'Selected products only']);
    expect(offerTerms(festiveSale), ['Up to ₹500 off', 'Applied automatically at checkout']);
  });

  test('quote JSON: the server numbers, the promotion and a coupon error', () {
    final q = Quote.fromJson({
      'subtotal_paise': 1999900, 'delivery_fee_paise': 0, 'discount_paise': 50000, 'total_paise': 1949900,
      'promotion': {'id': 'p1', 'title': 'Flat ₹500', 'code': 'DIWALI500', 'kind': 'flat'},
      'coupon_error': null,
    });
    expect((q.totalPaise, q.discountLabel, q.promotion!.kind), (1949900, 'DIWALI500', OfferKind.flat));
    final sale = Quote.fromJson({
      'subtotal_paise': 1999900, 'delivery_fee_paise': 4900, 'discount_paise': 0, 'total_paise': 2004800,
      'promotion': null, 'coupon_error': 'COUPON_MIN_ORDER', 'coupon_error_detail': '999900',
    });
    expect((sale.discountLabel, sale.couponError, sale.couponErrorDetail), (null, 'COUPON_MIN_ORDER', '999900'));
  });

  test('promotion status: ended beats paused beats scheduled', () {
    final now = DateTime(2026, 10, 30);
    Promotion p({bool active = true, int startDays = -1, int? endDays}) => Promotion(
          title: 'T',
          kind: OfferKind.flat,
          value: 100,
          isActive: active,
          startsAt: now.add(Duration(days: startDays)),
          endsAt: endDays == null ? null : now.add(Duration(days: endDays)),
        );
    expect(p().statusAt(now), PromotionStatus.running);
    expect(p(startDays: 2).statusAt(now), PromotionStatus.scheduled);
    expect(p(active: false, startDays: 2).statusAt(now), PromotionStatus.paused);
    expect(p(active: false, endDays: 0).statusAt(now), PromotionStatus.ended);
  });

  test('save payload: targets only for "some products", UTC dates, a round trip through fromJson', () {
    final p = Promotion(
      id: 'p1',
      title: 'Diwali picks',
      code: 'DIWALI10',
      kind: OfferKind.percent,
      value: 10,
      maxDiscountPaise: 100000,
      wholeOrder: false,
      targets: const {(TargetType.brand, 'b1'), (TargetType.collection, 'g1')},
      startsAt: DateTime.utc(2026, 10, 30, 6),
      endsAt: DateTime.utc(2026, 11, 5, 18),
    );
    final json = p.toJson();
    expect(json['applies_to'], 'items');
    expect(json['starts_at'], '2026-10-30T06:00:00.000Z');
    expect(json['targets'], unorderedEquals([
      {'target_type': 'brand', 'target_id': 'b1'},
      {'target_type': 'collection', 'target_id': 'g1'},
    ]));
    final back = Promotion.fromJson({...json, 'uses': 3, 'discount_total_paise': 15000});
    expect(back.targets, p.targets);
    expect((back.uses, back.maxDiscountPaise), (3, 100000));
    final whole = Promotion(title: 'All', kind: OfferKind.freeDelivery, value: 0, startsAt: DateTime(2026), targets: p.targets);
    expect(whole.toJson()['targets'], isEmpty, reason: 'a whole-order offer sends no targets');
    expect(whole.toJson().containsKey('id'), isFalse, reason: 'no id inserts');
    expect(json.containsKey('user_id'), isFalse, reason: 'a personal coupon keeps its owner');
  });

  test('generated codes are 8 easy-to-read characters that pass the DB rule', () {
    final r = Random(1);
    for (var i = 0; i < 50; i++) {
      final code = generateCode(r);
      expect(validateCode(code), isNull);
      expect(code, hasLength(8));
      expect(code, isNot(matches(RegExp('[01OIL]'))));
    }
    expect(targetsSummary({(TargetType.product, 'a'), (TargetType.product, 'b'), (TargetType.brand, 'c')}), '2 products · 1 brand');
  });
}
