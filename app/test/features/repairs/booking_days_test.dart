import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/repairs/data/booking_days.dart';

void main() {
  group('bookingDays', () {
    test('uses the IST date, not UTC: 19:00 UTC on 28 Oct is 29 Oct in India', () {
      final days = bookingDays(DateTime.utc(2026, 10, 28, 19));
      expect(days, hasLength(14));
      expect(isoDate(days.first), '2026-10-29');
      expect(isoDate(days.last), '2026-11-11');
    });

    test('is the same whatever the device zone (local DateTime input)', () {
      final instant = DateTime.utc(2026, 10, 28, 19);
      expect(bookingDays(instant.toLocal()), bookingDays(instant));
    });

    test('starts tomorrow once the evening slot is over (21:00 IST)', () {
      expect(isoDate(bookingDays(DateTime.utc(2026, 10, 29, 15, 29)).first), '2026-10-29'); // 20:59 IST
      expect(isoDate(bookingDays(DateTime.utc(2026, 10, 29, 15, 30)).first), '2026-10-30'); // 21:00 IST
    });

    test('rolls over months and years', () {
      final days = bookingDays(DateTime.utc(2026, 12, 25, 6));
      expect(days.map(isoDate), containsAllInOrder(['2026-12-31', '2027-01-01']));
      expect(isoDate(days.last), '2027-01-07');
    });

    test('stays inside the RLS window (today .. today + 30)', () {
      final now = DateTime.utc(2026, 10, 29, 16); // after 21:00 IST, so it starts tomorrow
      expect(bookingDays(now).last.difference(DateTime.utc(2026, 10, 29)).inDays, lessThanOrEqualTo(30));
    });
  });

  group('slotOver', () {
    final today = DateTime.utc(2026, 10, 29);
    final at1230Ist = DateTime.utc(2026, 10, 29, 7); // 12:30 IST

    test('only today’s ended slots are over', () {
      expect(slotOver(RepairSlot.morning, today, at1230Ist), isFalse);
      expect(slotOver(RepairSlot.morning, today, DateTime.utc(2026, 10, 29, 7, 30)), isTrue); // 13:00 IST
      expect(slotOver(RepairSlot.afternoon, today, DateTime.utc(2026, 10, 29, 7, 30)), isFalse);
      expect(slotOver(RepairSlot.morning, DateTime.utc(2026, 10, 30), DateTime.utc(2026, 10, 29, 15)), isFalse);
    });
  });

  test('bookingDayLabel says today for the IST date', () {
    final now = DateTime.utc(2026, 10, 29, 4);
    expect(bookingDayLabel(DateTime.utc(2026, 10, 29), now), 'today');
    expect(bookingDayLabel(DateTime.utc(2026, 10, 30), now), 'Fri 30 Oct');
  });
}
