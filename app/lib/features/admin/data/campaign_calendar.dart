import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';

// Campaign calendar (docs/GROWTH.md, item 6): the days worth an offer. India's holidays come from Google's public
// calendar feed (no key, cached on the phone 7 days); the shop days and seasons below are worked out here, so the
// calendar still has something offline.

enum EventKind { holiday, observance, shopDay, season }

/// One day (or a span of days, for a season) on the calendar. Dates are calendar days: midnight, no time zone.
class CalendarEvent {
  CalendarEvent({required this.name, required DateTime start, DateTime? end, required this.kind, this.big = false})
      : start = dayOf(start),
        end = dayOf(end ?? start);

  final String name;
  final DateTime start;
  final DateTime end; // the last day, inclusive
  final EventKind kind;
  final bool big; // worth an offer: the dashboard nudges when one is ≤ 7 days away with none planned

  bool covers(DateTime day) => !dayOf(day).isBefore(start) && !dayOf(day).isAfter(end);

  Map<String, Object> toJson() => {'n': name, 's': _ymd(start), 'e': _ymd(end), 'k': kind.name, 'b': big};

  static CalendarEvent fromJson(Map<String, dynamic> j) => CalendarEvent(
      name: j['n'] as String,
      start: DateTime.parse(j['s'] as String),
      end: DateTime.parse(j['e'] as String),
      kind: EventKind.values.byName(j['k'] as String),
      big: j['b'] == true);

  @override
  String toString() => '$name ${_ymd(start)}';
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Festivals that move shoppers here even when they aren't public holidays.
const _bigWords = [
  'diwali', 'deepavali', 'holi', 'dussehra', 'raksha', 'dhanteras', 'navratri', 'ganesh', 'janmashtami', 'eid', 'id-ul',
  'ramzan', 'bakrid', 'christmas', 'new year', 'makar', 'pongal', 'lohri', 'onam', 'karva', 'bhai', 'chhat', 'durga',
];

bool _isBig(String name) {
  final n = name.toLowerCase();
  return _bigWords.any(n.contains);
}

/// Every all-day VEVENT in an iCalendar file: folded lines joined, escapes undone, DTEND taken as exclusive (RFC 5545).
/// "Public holiday" in the description makes it a holiday (and big); anything else is an observance. Events without
/// a readable DTSTART or SUMMARY are skipped, never fatal.
List<CalendarEvent> parseIcs(String ics) {
  final lines = ics.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n[ \t]'), '').split('\n');
  final out = <CalendarEvent>[];
  Map<String, String>? event;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      event = {};
    } else if (line == 'END:VEVENT') {
      if (_eventOf(event ?? const {}) case final e?) out.add(e);
      event = null;
    } else if (event != null) {
      final colon = line.indexOf(':');
      if (colon > 0) event[line.substring(0, colon).split(';').first.toUpperCase()] = line.substring(colon + 1);
    }
  }
  return out;
}

DateTime? _icsDate(String? v) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(v?.trim() ?? '');
  if (m == null) return null;
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return d.month == int.parse(m[2]!) && d.day == int.parse(m[3]!) ? d : null; // 20260231 is not a day
}

String _unescape(String v) => v.replaceAllMapped(RegExp(r'\\([\\;,nN])'), (m) => switch (m[1]) { 'n' || 'N' => ' ', final c => c! }).trim();

CalendarEvent? _eventOf(Map<String, String> e) {
  final start = _icsDate(e['DTSTART']);
  final name = _unescape(e['SUMMARY'] ?? '');
  if (start == null || name.isEmpty) return null;
  final endExclusive = _icsDate(e['DTEND']);
  final end = endExclusive == null || !endExclusive.isAfter(start) ? start : endExclusive.subtract(const Duration(days: 1));
  final holiday = (e['DESCRIPTION'] ?? '').startsWith('Public holiday');
  return CalendarEvent(name: name, start: start, end: end, kind: holiday ? EventKind.holiday : EventKind.observance, big: holiday || _isBig(name));
}

/// The [n]th [weekday] (DateTime.monday..sunday) of [month].
DateTime nthWeekday(int year, int month, int weekday, int n) {
  final first = DateTime(year, month);
  return first.add(Duration(days: (weekday - first.weekday) % 7 + 7 * (n - 1)));
}

/// Days the shop sells on, worked out for [year].
List<CalendarEvent> shopDays(int year) => [
      CalendarEvent(name: 'New Year’s Day', start: DateTime(year), kind: EventKind.shopDay, big: true),
      CalendarEvent(name: 'Valentine’s Day', start: DateTime(year, 2, 14), kind: EventKind.shopDay, big: true),
      CalendarEvent(name: 'Women’s Day', start: DateTime(year, 3, 8), kind: EventKind.shopDay, big: true),
      CalendarEvent(name: 'Mother’s Day', start: nthWeekday(year, 5, DateTime.sunday, 2), kind: EventKind.shopDay, big: true),
      CalendarEvent(name: 'Father’s Day', start: nthWeekday(year, 6, DateTime.sunday, 3), kind: EventKind.shopDay, big: true),
      CalendarEvent(name: 'Friendship Day', start: nthWeekday(year, 8, DateTime.sunday, 1), kind: EventKind.shopDay, big: true),
      CalendarEvent(name: 'Teachers’ Day', start: DateTime(year, 9, 5), kind: EventKind.shopDay),
      CalendarEvent(name: 'Children’s Day', start: DateTime(year, 11, 14), kind: EventKind.shopDay),
      CalendarEvent(name: 'Men’s Day', start: DateTime(year, 11, 19), kind: EventKind.shopDay, big: true),
    ];

/// shortcut: rough seasons for this town (weddings, schools reopening); the owner should adjust the dates.
List<CalendarEvent> seasons(int year) => [
      CalendarEvent(name: 'Back to school', start: DateTime(year, 4), end: DateTime(year, 4, 15), kind: EventKind.season),
      CalendarEvent(name: 'Wedding season', start: DateTime(year, 4, 15), end: DateTime(year, 5, 31), kind: EventKind.season),
      CalendarEvent(name: 'Back to school', start: DateTime(year, 6, 15), end: DateTime(year, 7, 10), kind: EventKind.season),
      CalendarEvent(name: 'Wedding season', start: DateTime(year, 11, 15), end: DateTime(year, 12, 15), kind: EventKind.season),
    ];

String _key(CalendarEvent e) => '${_ymd(e.start)} ${e.name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')}';

/// The feed's events plus the shop days and seasons of [years], one per day and name, by date.
List<CalendarEvent> mergeEvents(List<CalendarEvent> feed, Iterable<int> years, {bool withSeasons = true}) {
  final seen = <String>{};
  return [
    for (final e in [...feed, for (final y in years) ...shopDays(y), if (withSeasons) for (final y in years) ...seasons(y)])
      if (seen.add(_key(e))) e,
  ]..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : (b.big ? 1 : 0) - (a.big ? 1 : 0));
}

/// "Men’s Day" → MEN5, "New Year’s Day" → NEWYEAR5, "Diwali/Deepavali" → DIWALI5: a code customers can read and type.
String suggestCode(String name, int percent) {
  const skip = {'day', 'the', 'of', 'and', 'international', 'national', 'world'};
  final words = name.replaceAll('’', "'").split(RegExp(r"[^A-Za-z']+")).where((w) => w.isNotEmpty);
  var base = '';
  for (final w in words) {
    if (skip.contains(w.toLowerCase())) {
      if (base.isEmpty) continue;
      break;
    }
    base += w.split("'").first.toUpperCase();
    if (w.contains("'") || base.length >= 4) break;
  }
  if (base.length > 12) base = base.substring(0, 12);
  final code = '$base$percent';
  return code.length >= 4 ? code : '${base}DAY$percent'; // promoCodes need 4+ characters
}

const istOffset = Duration(hours: 5, minutes: 30);

/// The IST instant [day] starts at (00:00 IST).
DateTime istStart(DateTime day) => DateTime.utc(day.year, day.month, day.day).subtract(istOffset);

/// Today's calendar day in IST, whatever the phone's zone.
DateTime istToday(DateTime now) => dayOf(now.toUtc().add(istOffset));

/// The editor's prefill for an event's offer: 5% off with the suggested code, from 00:00 IST on its first day to
/// 23:59 IST on its last, applied for customers automatically. Staff change anything before saving.
Promotion draftFor(CalendarEvent e, {int percent = 5}) => Promotion(
      title: '${e.name} sale'.length > 60 ? e.name.substring(0, 55) : '${e.name} sale',
      code: suggestCode(e.name, percent),
      kind: OfferKind.percent,
      value: percent,
      startsAt: istStart(e.start),
      endsAt: istStart(e.end).add(const Duration(hours: 23, minutes: 59)),
      autoApply: true,
    );

/// Offers that are on (not paused, not ended) at any moment of IST [day].
List<Promotion> offersOn(List<Promotion> all, DateTime day) {
  final from = istStart(day), to = from.add(const Duration(days: 1));
  return [
    for (final p in all)
      if (p.isActive && p.startsAt.isBefore(to) && (p.endsAt == null || p.endsAt!.isAfter(from))) p,
  ];
}

/// The first big event from today to 7 days ahead with no offer on any of its days, and how many days away.
({CalendarEvent event, int days})? nextUnplanned(List<CalendarEvent> events, List<Promotion> offers, DateTime now) {
  final today = istToday(now);
  for (final e in events) {
    if (!e.big || e.end.isBefore(today)) continue;
    final days = e.start.difference(today).inDays;
    if (days > 7) break; // sorted by date
    var planned = false;
    for (var d = e.start; !d.isAfter(e.end) && !planned; d = DateTime(d.year, d.month, d.day + 1)) {
      planned = offersOn(offers, d).isNotEmpty;
    }
    if (!planned) return (event: e, days: days < 0 ? 0 : days);
  }
  return null;
}

/// "today", "tomorrow", "in 5 days".
String inDays(int n) => switch (n) { 0 => 'today', 1 => 'tomorrow', _ => 'in $n days' };

const holidayFeedUrl =
    'https://calendar.google.com/calendar/ical/en.indian%23holiday%40group.v.calendar.google.com/public/basic.ics';
const _cacheKey = 'calendar_holidays_v1';
const _cacheDays = 7;

/// India's holidays from Google's feed: the phone's copy while it's under 7 days old, else a fresh fetch, else the old
/// copy, else none (the shop days and seasons still show). Only this year and later are kept.
final holidayFeedProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {} // no plugin (tests)
  final cached = prefs?.getString(_cacheKey);
  List<CalendarEvent> decode(String s) => [
        for (final e in (jsonDecode(s)['events'] as List)) CalendarEvent.fromJson(e as Map<String, dynamic>),
      ];
  if (cached != null) {
    final at = DateTime.tryParse(jsonDecode(cached)['at'] as String? ?? '');
    if (at != null && DateTime.now().difference(at).inDays < _cacheDays) return decode(cached);
  }
  try {
    final res = await http.get(Uri.parse(holidayFeedUrl)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}');
    final thisYear = DateTime.now().year;
    final events = [for (final e in parseIcs(utf8.decode(res.bodyBytes))) if (e.end.year >= thisYear) e];
    await prefs?.setString(_cacheKey, jsonEncode({'at': DateTime.now().toIso8601String(), 'events': [for (final e in events) e.toJson()]}));
    return events;
  } catch (_) {
    return cached == null ? const [] : decode(cached);
  }
});

/// The calendar's clock (tests pin it).
final calendarNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// Feed + shop days (+ seasons) for last year to two years ahead.
final campaignEventsProvider = FutureProvider.autoDispose.family<List<CalendarEvent>, bool>((ref, withSeasons) async {
  final year = istToday(ref.watch(calendarNowProvider)).year;
  return mergeEvents(await ref.watch(holidayFeedProvider.future), [year - 1, year, year + 1, year + 2], withSeasons: withSeasons);
});
