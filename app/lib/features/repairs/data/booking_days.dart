import 'package:intl/intl.dart';

import '../../../core/models/models.dart';

/// The shop runs on India time whatever the phone's zone is set to (the RLS date window is IST too).
const istOffset = Duration(hours: 5, minutes: 30);

/// Wall-clock time in India, as a UTC DateTime whose fields read as IST.
DateTime istNow([DateTime? now]) => (now ?? DateTime.now()).toUtc().add(istOffset);

/// Hour (IST) each slot ends. Mirrors the text in [RepairSlot.hours].
const slotEndHour = {RepairSlot.morning: 13, RepairSlot.afternoon: 17, RepairSlot.evening: 21};

/// Whether [slot] on [day] (an IST date from [bookingDays]) has already ended at [now].
bool slotOver(RepairSlot slot, DateTime day, DateTime now) =>
    !istNow(now).isBefore(DateTime.utc(day.year, day.month, day.day, slotEndHour[slot]!));

/// The next [count] bookable IST dates (UTC midnights), from today, or from tomorrow once today's last slot is over.
List<DateTime> bookingDays(DateTime now, {int count = 14}) {
  final ist = istNow(now);
  final today = DateTime.utc(ist.year, ist.month, ist.day);
  final start = slotOver(RepairSlot.values.last, today, now) ? 1 : 0;
  return [for (var i = start; i < start + count; i++) DateTime.utc(today.year, today.month, today.day + i)];
}

/// `preferred_date` column format.
String isoDate(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

bool isIstToday(DateTime day, DateTime now) {
  final ist = istNow(now);
  return day.year == ist.year && day.month == ist.month && day.day == ist.day;
}

/// "today" or "Thu 30 Oct".
String bookingDayLabel(DateTime day, DateTime now) => isIstToday(day, now) ? 'today' : DateFormat('EEE d MMM').format(day);
