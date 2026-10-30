import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../admin/data/admin.dart';

enum RefundStatus {
  pending('pending', 'On its way'),
  processed('processed', 'Refunded'),
  failed('failed', 'Failed');

  const RefundStatus(this.value, this.label);
  final String value;
  final String label;

  static RefundStatus parse(String v) => values.firstWhere((s) => s.value == v);
}

/// A refund made in the app (`refunds`). Refunds made in the Razorpay dashboard only show as the order's Refunded.
class Refund {
  const Refund({
    required this.id,
    required this.amountPaise,
    required this.full,
    required this.status,
    required this.createdAt,
    this.instant = false,
    this.speedProcessed,
    this.failure,
    this.items = const [],
  });

  final String id;
  final int amountPaise;
  final bool full;
  final bool instant;
  final RefundStatus status;
  final String? speedProcessed; // instant | normal, once Razorpay says
  final String? failure;
  final DateTime createdAt;
  final List<String> items; // product names of the lines it pays back

  factory Refund.fromJson(Map<String, dynamic> j) => Refund(
        id: j['id'],
        amountPaise: j['amount_paise'],
        full: j['full_refund'] == true,
        instant: j['instant'] == true,
        status: RefundStatus.parse(j['status']),
        speedProcessed: j['speed_processed'],
        failure: j['failure'],
        createdAt: DateTime.parse(j['created_at']),
        items: [for (final i in (j['items'] as List? ?? const [])) (i as Map)['product_name'] as String],
      );
}

/// An order line as a refund sees it: what was paid for it (price × qty − its share of the discount).
class RefundLine {
  const RefundLine({required this.id, required this.name, required this.qty, required this.paidPaise, this.refundId});

  final String id;
  final String name;
  final int qty;
  final int paidPaise;
  final String? refundId; // a pending or processed refund already pays it back

  factory RefundLine.fromJson(Map<String, dynamic> j) => RefundLine(
        id: j['id'],
        name: [j['product_name'], if ((j['variant_name'] as String? ?? '').isNotEmpty) j['variant_name']].join(' · '),
        qty: j['qty'],
        paidPaise: (j['unit_price_paise'] as int) * (j['qty'] as int) - ((j['discount_paise'] as int?) ?? 0),
        refundId: j['refund_id'],
      );
}

class PaymentLink {
  const PaymentLink({
    required this.id,
    required this.amountPaise,
    required this.description,
    required this.customerPhone,
    required this.status,
    required this.expiresAt,
    this.orderId,
    this.customerName,
    this.shortUrl,
    this.createdAt,
  });

  final String id;
  final String? orderId;
  final int amountPaise;
  final String description;
  final String? customerName;
  final String customerPhone;
  final String status; // created | paid | cancelled | expired
  final String? shortUrl;
  final DateTime expiresAt;
  final DateTime? createdAt;

  bool get isOpen => status == 'created' && shortUrl != null && expiresAt.isAfter(DateTime.now());

  /// "Paid", "Open until 2 Nov 2026, 3:30 pm", "Expired", "Cancelled"
  String get statusLabel => switch (status) {
        'paid' => 'Paid',
        'cancelled' => 'Cancelled',
        _ when !isOpen => 'Expired',
        _ => 'Open until ${formatDateTime(expiresAt)}',
      };

  factory PaymentLink.fromJson(Map<String, dynamic> j) => PaymentLink(
        id: j['id'],
        orderId: j['order_id'],
        amountPaise: j['amount_paise'],
        description: j['description'],
        customerName: j['customer_name'],
        customerPhone: j['customer_phone'],
        status: j['status'],
        shortUrl: j['short_url'],
        expiresAt: DateTime.parse(j['expires_at']),
        createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at']),
      );
}

/// A chargeback or other dispute Razorpay reported (staff only).
class Dispute {
  const Dispute({required this.id, required this.amountPaise, required this.status, this.reason, this.respondBy});

  final String id;
  final int amountPaise;
  final String status; // open | under_review | won | lost | closed
  final String? reason;
  final DateTime? respondBy;

  bool get open => status == 'open' || status == 'action_required';

  factory Dispute.fromJson(Map<String, dynamic> j) => Dispute(
        id: j['id'],
        amountPaise: j['amount_paise'],
        status: j['status'],
        reason: j['reason'],
        respondBy: j['respond_by'] == null ? null : DateTime.parse(j['respond_by']),
      );
}

/// The WhatsApp message for a link: who it's for, the amount, the link (WhatsApp previews it) and until when.
String paymentLinkText(PaymentLink l) {
  final hi = l.customerName == null ? 'Hi' : 'Hi ${l.customerName!.split(' ').first}';
  final what = l.description.replaceFirst('Shyam Mobiles order ', 'order ');
  return [
    '$hi, here’s your Shyam Mobiles payment link for $what: ${formatInr(l.amountPaise)}.',
    'Pay by UPI, card or netbanking. It works until ${formatDateTime(l.expiresAt)}.',
    l.shortUrl ?? '',
  ].join('\n');
}

/// An order's refunds, oldest first (RLS: the customer's own orders, any for staff).
final orderRefundsProvider = FutureProvider.autoDispose.family<List<Refund>, String>((ref, orderId) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('refunds')
      .select('*, items:order_items(product_name)')
      .eq('order_id', orderId)
      .order('created_at');
  return [for (final r in rows) Refund.fromJson(r)];
});

typedef OrderPayments = ({List<RefundLine> lines, List<Refund> refunds, List<PaymentLink> links, List<Dispute> disputes});

/// Staff: an order's lines for refunds, its refunds, payment links (newest first) and disputes.
final orderPaymentsProvider = FutureProvider.autoDispose.family<OrderPayments, String>((ref, orderId) async {
  final db = ref.watch(supabaseProvider);
  final (lines, refunds, links, disputes) = await (
    db.from('order_items').select('id, product_name, variant_name, qty, unit_price_paise, discount_paise, refund_id')
        .eq('order_id', orderId).order('unit_price_paise', ascending: false).order('id'),
    ref.watch(orderRefundsProvider(orderId).future),
    db.from('payment_links').select().eq('order_id', orderId).order('created_at', ascending: false),
    db.from('disputes').select().eq('order_id', orderId).order('created_at', ascending: false),
  ).wait;
  return (
    lines: [for (final l in lines) RefundLine.fromJson(l)],
    refunds: refunds,
    links: [for (final l in links) PaymentLink.fromJson(l)],
    disputes: [for (final d in disputes) Dispute.fromJson(d)],
  );
});

/// Staff: the 50 newest payment links, for orders or typed amounts.
final paymentLinksProvider = FutureProvider.autoDispose<List<PaymentLink>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('payment_links').select().order('created_at', ascending: false).limit(50);
  return [for (final r in rows) PaymentLink.fromJson(r)];
});

/// What's left to refund on [o]: the total minus refunds Razorpay has processed (the server computes the same).
int refundablePaise(Order o, List<Refund> refunds) =>
    o.totalPaise - refunds.where((r) => r.status == RefundStatus.processed).fold(0, (n, r) => n + r.amountPaise);

/// Which refunds staff may start on [o]: everything left (a cancelled or delivered order), and/or chosen lines (an
/// order that isn't cancelled). Neither while a refund is on its way, or when it wasn't paid online.
({bool full, bool items}) refundChoices(Order o, List<Refund> refunds) {
  final paid = o.paymentMethod == PaymentMethod.razorpay && o.paymentStatus == PaymentStatus.paid;
  if (!paid || refunds.any((r) => r.status == RefundStatus.pending) || refundablePaise(o, refunds) < 100) {
    return (full: false, items: false);
  }
  return (
    full: o.status == OrderStatus.cancelled || o.status == OrderStatus.delivered,
    items: o.status != OrderStatus.cancelled && o.status != OrderStatus.pendingPayment,
  );
}

/// A payment link makes sense while the order is unpaid and not cancelled.
bool canSendLink(Order o) =>
    (o.paymentStatus == PaymentStatus.pending || o.paymentStatus == PaymentStatus.failed) &&
    o.status != OrderStatus.cancelled &&
    o.status != OrderStatus.refunded;

void _paymentsChanged(WidgetRef ref, String? orderId) {
  if (orderId != null) {
    ref.invalidate(orderPaymentsProvider(orderId));
    ref.invalidate(orderRefundsProvider(orderId));
    ref.invalidate(adminOrderProvider(orderId));
  }
  ref.invalidate(paymentLinksProvider);
  ref.invalidate(adminDashboardProvider);
  ref.invalidate(adminOrdersProvider);
}

/// `refund-payment`: Razorpay's Refunds API for [orderId], everything left or [itemIds]. Returns its status
/// (processed, pending or failed).
Future<RefundStatus> startRefund(WidgetRef ref, String orderId,
    {List<String>? itemIds, bool restock = false, bool instant = false}) async {
  try {
    final res = await ref.read(supabaseProvider).functions.invoke('refund-payment', body: {
      'order_id': orderId,
      'item_ids': ?itemIds,
      'restock': restock,
      'instant': instant,
    });
    return RefundStatus.parse((res.data as Map)['status']);
  } finally {
    _paymentsChanged(ref, orderId); // a refusal or timeout changes what's on record too
  }
}

/// `payment-link`: the order's link (an open one is reused), or one for a typed amount.
Future<PaymentLink> createPaymentLink(WidgetRef ref,
    {String? orderId, int? amountPaise, String? phone, String? name, String? description}) async {
  final res = await ref.read(supabaseProvider).functions.invoke('payment-link', body: orderId != null
      ? {'order_id': orderId}
      : {'amount_paise': amountPaise, 'phone': phone, 'name': name, 'description': description});
  _paymentsChanged(ref, orderId);
  return PaymentLink.fromJson(Map<String, dynamic>.from(res.data as Map));
}

Future<void> cancelPaymentLink(WidgetRef ref, PaymentLink link) async {
  await ref.read(supabaseProvider).functions.invoke('payment-link', body: {'cancel': link.id});
  _paymentsChanged(ref, link.orderId);
}
