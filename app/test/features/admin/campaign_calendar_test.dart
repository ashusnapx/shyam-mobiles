// Campaign calendar data: Google's holiday feed (a saved real copy, 2026), the shop days worked out in code
// (2026–2028), code suggestions, the editor prefill and the dashboard's "no offer planned" nudge.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/campaign_calendar.dart';

final _fixture = File('test/fixtures/holidays_in_india_2026.ics').readAsStringSync();

CalendarEvent _named(List<CalendarEvent> all, String name) => all.firstWhere((e) => e.name == name);

void main() {
  test('the real feed: 58 all-day events in 2026, 18 public holidays, folded lines joined', () {
    final all = parseIcs(_fixture);
    expect(all.length, 58);
    expect(all.where((e) => e.kind == EventKind.holiday).length, 18);
    expect(all.every((e) => e.start == e.end && e.start.year == 2026), isTrue); // DTEND is exclusive
    final diwali = _named(all, 'Diwali/Deepavali');
    expect((diwali.start, diwali.kind, diwali.big), (DateTime(2026, 11, 8), EventKind.holiday, true));
    expect(_named(all, 'Bhai Duj').big, isTrue); // a festival that isn't a holiday
    expect(_named(all, 'Chhat Puja (Pratihar Sashthi/Surya Sashthi)').big, isTrue);
    expect(_named(all, 'Hazarat Ali\'s Birthday').big, isFalse);
  });

  test('worst-case input: junk is skipped, never fatal', () {
    const ics = 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART;VALUE=DATE:20260231\nSUMMARY:No such day\nEND:VEVENT\n'
        'BEGIN:VEVENT\nSUMMARY:No start\nEND:VEVENT\n'
        'BEGIN:VEVENT\nDTSTART;VALUE=DATE:20261001\nSUMMARY:\nEND:VEVENT\n'
        'BEGIN:VEVENT\r\nDTSTART:20261225T000000Z\r\nDTEND;VALUE=DATE:20261228\r\nSUMMARY:Year-end\\, sale\\n\r\n  week\r\nDESCRIPTION:Public h\r\n oliday\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\nDTSTART;VALUE=DATE:20260101\nDTEND;VALUE=DATE:20251231\nSUMMARY:Backwards\nEND:VEVENT\n'
        'BEGIN:VEVENT\nDTSTART;VALUE=DATE:20260301\nSUMMARY:Never closed\n';
    final all = parseIcs(ics);
    expect(all.map((e) => e.name), ['Year-end, sale  week', 'Backwards']);
    expect((all[0].start, all[0].end, all[0].kind), (DateTime(2026, 12, 25), DateTime(2026, 12, 27), EventKind.holiday));
    expect(all[1].end, DateTime(2026)); // an end before the start: one day
    expect(parseIcs(''), isEmpty);
    expect(parseIcs('garbage\u0000\n:\n;;;'), isEmpty);
  });

  test('shop days 2026–2028: the fixed ones and the nth Sundays', () {
    final want = {
      2026: ['2026-05-10', '2026-06-21', '2026-08-02'],
      2027: ['2027-05-09', '2027-06-20', '2027-08-01'],
      2028: ['2028-05-14', '2028-06-18', '2028-08-06'],
    };
    for (final MapEntry(key: y, value: sundays) in want.entries) {
      final days = {for (final e in shopDays(y)) e.name: e.start.toIso8601String().substring(0, 10)};
      expect([days['Mother’s Day'], days['Father’s Day'], days['Friendship Day']], sundays);
      expect(days['Men’s Day'], '$y-11-19');
      expect(days['Women’s Day'], '$y-03-08');
      expect(days['Teachers’ Day'], '$y-09-05');
      expect(days['Children’s Day'], '$y-11-14');
      expect(days['Valentine’s Day'], '$y-02-14');
      expect(days['New Year’s Day'], '$y-01-01');
      for (final s in sundays) expect(DateTime.parse(s).weekday, DateTime.sunday);
    }
  });

  test('merged: the feed’s New Year’s Day and ours are one; seasons only when asked', () {
    final all = mergeEvents(parseIcs(_fixture), [2026]);
    expect(all.where((e) => e.start == DateTime(2026) && e.name.toLowerCase().startsWith('new year')).length, 1);
    expect(all.any((e) => e.kind == EventKind.season), isTrue);
    expect(mergeEvents(const [], [2026], withSeasons: false).any((e) => e.kind == EventKind.season), isFalse);
    for (var i = 1; i < all.length; i++) {
      expect(all[i].start.isBefore(all[i - 1].start), isFalse);
    }
  });

  test('code suggestions customers can read', () {
    expect(suggestCode('Men’s Day', 5), 'MEN5');
    expect(suggestCode("New Year's Day", 5), 'NEWYEAR5');
    expect(suggestCode('Diwali/Deepavali', 10), 'DIWALI10');
    expect(suggestCode('Teachers’ Day', 5), 'TEACHERS5');
    expect(suggestCode('Id', 5), 'IDDAY5');
    expect(suggestCode('International Yoga Day', 5), 'YOGA5');
    for (final e in mergeEvents(parseIcs(_fixture), [2026])) {
      expect(RegExp(r'^[A-Z0-9]{4,20}$').hasMatch(suggestCode(e.name, 5)), isTrue, reason: e.name);
    }
  });

  test('the prefill: 5% with the code, 00:00 to 23:59 IST, applied for customers', () {
    final p = draftFor(_named(shopDays(2026), 'Men’s Day'));
    expect((p.id, p.title, p.code, p.kind, p.value, p.autoApply), (null, 'Men’s Day sale', 'MEN5', OfferKind.percent, 5, true));
    expect(p.startsAt, DateTime.utc(2026, 11, 18, 18, 30));
    expect(p.endsAt, DateTime.utc(2026, 11, 19, 18, 29));
  });

  test('the nudge: the next big day within 7 days with no offer on it', () {
    final events = mergeEvents(parseIcs(_fixture), [2026], withSeasons: false);
    final now = DateTime.utc(2026, 11, 19, 4, 30); // 10:00 IST
    var next = nextUnplanned(events, const [], now)!;
    expect((next.event.name, next.days), ('Men’s Day', 0));
    final menSale = draftFor(_named(events, 'Men’s Day'));
    next = nextUnplanned(events, [Promotion(id: 'm', title: menSale.title, kind: OfferKind.percent, value: 5, startsAt: menSale.startsAt, endsAt: menSale.endsAt)], now)!;
    expect((next.event.name, next.days), ('Guru Nanak Jayanti', 5));
    final paused = Promotion(id: 'p', title: 'x', kind: OfferKind.percent, value: 5, startsAt: DateTime.utc(2026, 11), isActive: false);
    expect(offersOn([paused], DateTime(2026, 11, 19)), isEmpty);
    expect(nextUnplanned(events, const [], DateTime.utc(2026, 12, 1)), isNull); // nothing big until the 24th
    expect(nextUnplanned(events, const [], DateTime.utc(2026, 12, 18))?.event.name, 'Christmas Eve');
    expect(inDays(0), 'today');
    expect(inDays(1), 'tomorrow');
    expect(inDays(5), 'in 5 days');
  });
}
