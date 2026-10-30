import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/rules.dart';

void main() {
  group('orderTransitions', () {
    // Copied from admin_update_order in supabase/migrations/20261028000200_rpcs.sql.
    const sql = {
      ('pending_payment', 'cancelled'),
      ('confirmed', 'packed'), ('confirmed', 'cancelled'),
      ('packed', 'shipped'), ('packed', 'cancelled'),
      ('shipped', 'delivered'),
      ('delivered', 'refunded'),
    };

    test('matches the SQL table exactly', () {
      final app = {
        for (final e in orderTransitions.entries)
          for (final to in e.value) (e.key.value, to.value),
      };
      expect(app, sql);
    });

    test('terminal states have no next step', () {
      expect(nextOrderStatuses(OrderStatus.cancelled), isEmpty);
      expect(nextOrderStatuses(OrderStatus.refunded), isEmpty);
    });
  });

  test('repairNextStep walks the SPEC chain and stops at completed', () {
    var s = RepairStatus.requested;
    final seen = [s];
    while (repairNextStep[s] != null) {
      seen.add(s = repairNextStep[s]!);
    }
    expect(seen, [
      RepairStatus.requested,
      RepairStatus.confirmed,
      RepairStatus.inProgress,
      RepairStatus.ready,
      RepairStatus.completed,
    ]);
  });

  group('repair steps (admin_update_repair, admin_set_repair_quote)', () {
    RepairBooking b(RepairStatus s, RepairQuoteStatus q) => RepairBooking(
          id: '1',
          number: 'RP100012',
          deviceBrand: 'Vivo',
          deviceModel: 'Y20',
          issue: RepairIssue.battery,
          preferredDate: DateTime(2026, 10, 30),
          slot: RepairSlot.evening,
          contactPhone: '+919876543210',
          status: s,
          createdAt: DateTime(2026, 10, 29),
          quotePaise: q == RepairQuoteStatus.none ? null : 20000,
          quoteStatus: q,
        );

    test('starting and finishing the work wait for an approved quote, nothing else does', () {
      for (final s in RepairStatus.values) {
        for (final q in RepairQuoteStatus.values) {
          final gated = (s == RepairStatus.confirmed || s == RepairStatus.inProgress) && q != RepairQuoteStatus.approved;
          expect(repairStepBlocker(b(s, q)) != null, gated, reason: '${s.value} ${q.value}');
        }
      }
      expect(repairStepBlocker(b(RepairStatus.confirmed, RepairQuoteStatus.pending)), 'Waiting for the customer to approve ₹200.');
      expect(repairStepBlocker(b(RepairStatus.inProgress, RepairQuoteStatus.declined)), contains('declined ₹200'));
      expect(repairStepBlocker(b(RepairStatus.confirmed, RepairQuoteStatus.none)), startsWith('Send a quote first'));
    });

    test('quotes only before the repair is ready', () {
      expect([for (final s in RepairStatus.values) if (canQuoteRepair(s)) s],
          [RepairStatus.requested, RepairStatus.confirmed, RepairStatus.inProgress]);
    });

    test('the WhatsApp text follows the quote', () {
      expect(repairUpdateText(b(RepairStatus.confirmed, RepairQuoteStatus.approved)), endsWith('Agreed price: ₹200.'));
      expect(repairUpdateText(b(RepairStatus.confirmed, RepairQuoteStatus.declined)), contains('You declined the quote of ₹200.'));
      expect(repairUpdateText(b(RepairStatus.completed, RepairQuoteStatus.approved)), isNot(contains('₹')));
    });
  });

  group('rupees <-> paise', () {
    test('parses plain, grouped, symbol and decimal input', () {
      expect(parseRupees('74999'), 7499900);
      expect(parseRupees('74,999'), 7499900);
      expect(parseRupees('1,29,999'), 12999900);
      expect(parseRupees(' ₹ 499.5 '), 49950);
      expect(parseRupees('0.99'), 99);
      expect(parseRupees('0'), 0);
    });

    test('rejects junk, negatives, 3 decimals and overflow', () {
      for (final bad in ['', 'abc', '-5', '1.234', '.5', '1e5', '1.2.3', '21474837']) {
        expect(parseRupees(bad), isNull, reason: bad);
      }
      expect(parseRupees('21474836.47'), 2147483647); // int4 max
    });

    test('round-trips through rupeesText', () {
      for (final p in [0, 99, 49950, 7499900, 12999901]) {
        expect(parseRupees(rupeesText(p)), p);
      }
      expect(rupeesText(7499950), '74999.50');
      expect(rupeesText(7499900), '74999');
    });
  });

  test('shortInr', () {
    expect(shortInr(4999900), '₹49,999');
    expect(shortInr(4999999), '₹49,999');
    expect(shortInr(48200000), '₹4.82L');
    expect(shortInr(48299999), '₹4.82L'); // rounds down
    expect(shortInr(45000000), '₹4.5L');
    expect(shortInr(50000000), '₹5L');
    expect(shortInr(1000000000), '₹1Cr');
    expect(shortInr(1250000000), '₹1.25Cr');
    expect(shortInr(0), '₹0');
  });

  test('new brand names start with a capital letter', () {
    expect(brandDisplayName('itel'), 'Itel');
    expect(brandDisplayName('  tecno   mobile '), 'Tecno mobile');
    expect(brandDisplayName('iQOO'), 'IQOO');
    expect(brandDisplayName('   '), '');
  });

  group('IMEIs', () {
    const a = '352099214488120', b = '352099214488138';

    test('accepts qty distinct 15-digit values', () {
      expect(imeisError([a], 1), isNull);
      expect(imeisError([a, b], 2), isNull);
    });

    test('rejects wrong count, bad digits and repeats', () {
      expect(imeisError([a], 2), 'Enter 2 IMEIs');
      expect(imeisError([], 1), 'Enter 1 IMEI');
      expect(imeisError(['35209921448812'], 1), isNotNull); // 14 digits
      expect(imeisError(['35209921448812x'], 1), isNotNull);
      expect(imeisError([a, a], 2), contains('repeated'));
      expect(imeiFieldError(a), isNull);
      expect(imeiFieldError('3520992144881200'), isNotNull);
      expect(imeiFieldError('352099214488121'), contains('digit looks wrong')); // Luhn typo
      expect(imeisError(['352099214488121'], 1), contains('digit wrong'));
    });
  });

  group('slugify', () {
    test('makes DB-valid slugs', () {
      expect(slugify('Samsung Galaxy S25 5G'), 'samsung-galaxy-s25-5g');
      expect(slugify('  Apple iPhone 16 Pro Max (256 GB) '), 'apple-iphone-16-pro-max-256-gb');
      expect(slugify('Galaxy S25+'), 'galaxy-s25-plus');
      expect(slugify('Redmi Note 14 Pro+ 5G'), 'redmi-note-14-pro-plus-5g');
      expect(slugify('Spigen — GlasTR, screen guard!'), 'spigen-glastr-screen-guard');
      for (final s in ['OnePlus 13R', 'vivo X200 Pro', 'Nothing Phone (3a)']) {
        expect(slugPattern.hasMatch(slugify(s)), isTrue, reason: s);
      }
    });

    test('empty when nothing usable', () => expect(slugify('—'), ''));
  });

  test('variantName joins the filled parts', () {
    expect(variantName(['8 GB', ' 256 GB ', 'Black']), '8 GB · 256 GB · Black');
    expect(variantName(['', '128 GB', '']), '128 GB');
  });

  group('WhatsApp update text', () {
    Order order(OrderStatus s, {String? courier, String? tracking, PaymentStatus pay = PaymentStatus.pending}) => Order(
          id: '1',
          number: 'SM100023',
          status: s,
          paymentMethod: PaymentMethod.razorpay,
          paymentStatus: pay,
          subtotalPaise: 7499900,
          deliveryFeePaise: 0,
          totalPaise: 7499900,
          address: const Address(name: 'Asha', phone: '+919876543210', line1: 'x', city: 'x', state: 'x', pincode: '110001'),
          createdAt: DateTime(2026, 10, 27),
          courier: courier,
          trackingNumber: tracking,
        );

    test('orders say the status in plain words', () {
      expect(orderUpdateText(order(OrderStatus.packed)), 'Hi Asha, your Shyam Mobiles order SM100023 is packed and will ship soon.');
      expect(orderUpdateText(order(OrderStatus.shipped, courier: 'Delhivery', tracking: '1490')),
          contains('on its way with Delhivery (tracking 1490)'));
      expect(orderUpdateText(order(OrderStatus.cancelled, pay: PaymentStatus.paid)), contains('refund of ₹74,999'));
      for (final s in OrderStatus.values) {
        expect(orderUpdateText(order(s)), isNot(contains('_')), reason: s.value);
      }
    });

    test('repairs include the slot and an open quote', () {
      final b = RepairBooking(
        id: '1',
        number: 'RP100012',
        deviceBrand: 'Samsung',
        deviceModel: 'Galaxy S23',
        issue: RepairIssue.screen,
        preferredDate: DateTime(2026, 10, 30),
        slot: RepairSlot.afternoon,
        contactPhone: '+919876543210',
        status: RepairStatus.confirmed,
        createdAt: DateTime(2026, 10, 29),
        quotePaise: 249900,
        quoteStatus: RepairQuoteStatus.pending,
      );
      expect(
        repairUpdateText(b),
        'Hi, your Shyam Mobiles repair RP100012 (Samsung Galaxy S23) is confirmed for Fri 30 Oct, afternoon '
        '(1 pm – 5 pm). Quote: ₹2,499. Approve or decline it in the app under Repairs. Work starts only after you '
        'approve it.',
      );
    });
  });

  group('parseMapPin', () {
    const place = 'https://www.google.com/maps/place/Shyam+Mobile+Center/@24.0670269,82.6281759,17z/data=!3m1!4b1!4m6!3m5'
        '!1s0x398f36a1677a416d:0x2f223fc80896dee5!8m2!3d24.0670269!4d82.6307508!16s%2Fg%2F11g68z4gkx';

    test('reads the founder\'s search link, an @ link, q/ll params and plain text', () {
      expect(parseMapPin('https://www.google.com/maps/search/?api=1&query=24.0665176,82.6259026'), (lat: 24.0665176, lng: 82.6259026));
      expect(parseMapPin('https://www.google.com/maps/search/?api=1&query=24.0665176%2C82.6259026'), (lat: 24.0665176, lng: 82.6259026));
      expect(parseMapPin('https://www.google.com/maps/@24.0665176,82.6259026,18z'), (lat: 24.0665176, lng: 82.6259026));
      expect(parseMapPin('https://maps.google.com/?q=24.0665,82.6259'), (lat: 24.0665, lng: 82.6259));
      expect(parseMapPin('https://maps.google.com/?ll=24.0665,82.6259&z=17'), (lat: 24.0665, lng: 82.6259));
      expect(parseMapPin('  24.0665176, 82.6259026 '), (lat: 24.0665176, lng: 82.6259026));
    });

    test('prefers the place pin over the @ viewport centre', () {
      expect(parseMapPin(place), (lat: 24.0670269, lng: 82.6307508));
    });

    test('rejects pins outside India and anything without one', () {
      expect(parseMapPin('https://www.google.com/maps/@51.5072,-0.1276,12z'), isNull); // London
      expect(parseMapPin('40.7128, -74.0060'), isNull);
      for (final bad in ['', 'Rajeev Complex, Waidhan', 'https://maps.app.goo.gl/AbCdEf123', '24.06', 'lat, lng', '100%']) {
        expect(parseMapPin(bad), isNull, reason: bad);
      }
    });

    test('only full place links are kept as the listing', () {
      expect(isMapsPlaceLink(place), isTrue);
      expect(isMapsPlaceLink('https://www.google.com/maps/search/?api=1&query=24.0665176,82.6259026'), isFalse);
      expect(isMapsPlaceLink('24.0670269, 82.6307508'), isFalse);
    });
  });
}
