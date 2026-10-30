import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/repairs/screens/repair_detail_screen.dart';
import 'package:shyam_mobiles/features/repairs/widgets/repair_widgets.dart';

import 'layout_harness.dart';

void main() {
  test('the next-step copy never promises work before the customer approves', () {
    expect(repairStepCopy(testBooking()), 'Check the price below. Work starts only after you approve it.');
    expect(repairStepCopy(testBooking(quote: null)), contains('send you the price here'));
    expect(repairStepCopy(testBooking(quoteStatus: RepairQuoteStatus.approved)), 'Price approved. We’ll start the repair soon.');
    expect(repairStepCopy(testBooking(quoteStatus: RepairQuoteStatus.declined)), contains('or you can cancel'));
    expect(repairStepCopy(testBooking(status: RepairStatus.inProgress, quoteStatus: RepairQuoteStatus.declined)),
        isNot(contains('cancel')), reason: 'customers can’t cancel once the phone is opened');
    expect(repairStepCopy(testBooking(status: RepairStatus.cancelled)), 'This booking is cancelled.',
        reason: 'a pending quote on a cancelled booking asks for nothing');
  });

  test('timeline titles: steps, quotes and notes', () {
    final e = testBooking().events;
    expect([for (final (i, x) in e.indexed) repairEventTitle(x, i == 0 ? null : e[i - 1])],
        ['Requested', 'Confirmed', 'Quote sent · ₹2,499']);
    final note = RepairEvent(id: 9, status: RepairStatus.confirmed, createdAt: DateTime(2026, 10, 30), note: 'Hi');
    expect(repairEventTitle(note, e[1]), 'Note from the store');
  });
}
