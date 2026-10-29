import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../cart/data/cart.dart';

const ordersPageSize = 20;

typedef OrdersPage = ({List<Order> orders, bool hasMore});

/// The signed-in user's orders, newest first. Filtered by user_id: RLS also lets admins read everyone's.
final ordersProvider = AsyncNotifierProvider.autoDispose<OrdersNotifier, OrdersPage>(OrdersNotifier.new);

class OrdersNotifier extends AsyncNotifier<OrdersPage> {
  bool _loadingMore = false;

  Future<OrdersPage> _fetch(String? uid, int from) async {
    if (uid == null) return (orders: const <Order>[], hasMore: false);
    final rows = await ref
        .read(supabaseProvider)
        .from('orders')
        .select('*, items:order_items(*)')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .range(from, from + ordersPageSize - 1);
    return (orders: [for (final r in rows) Order.fromJson(r)], hasMore: rows.length == ordersPageSize);
  }

  @override
  Future<OrdersPage> build() => _fetch(ref.watch(currentUserIdProvider), 0);

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loadingMore || state.isLoading) return;
    _loadingMore = true;
    try {
      final next = await _fetch(ref.read(currentUserIdProvider), current.orders.length);
      if (ref.mounted) state = AsyncData((orders: [...current.orders, ...next.orders], hasMore: next.hasMore));
    } finally {
      _loadingMore = false;
    }
  }
}

/// One order with its items and timeline.
final orderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('orders')
      .select('*, items:order_items(*), events:order_events(*)')
      .eq('id', id)
      .maybeSingle();
  if (row == null) throw const PostgrestException(message: 'NOT_FOUND');
  return Order.fromJson(row);
});

/// Puts a closed order's items back in the cart, capped by today's stock. Returns how many lines came back.
Future<int> reorder(SupabaseClient db, CartNotifier cart, Order o) async {
  final ids = [for (final i in o.items) ?i.variantId];
  if (ids.isEmpty) return 0;
  final rows = await db.from('variants').select().inFilter('id', ids);
  final variants = {for (final r in rows) r['id'] as String: Variant.fromJson(r)};
  var added = 0;
  for (final i in o.items) {
    final v = variants[i.variantId];
    if (v == null || !v.inStock) continue;
    await cart.add(v, qty: i.qty);
    added++;
  }
  return added;
}

class TimelineStep {
  const TimelineStep({required this.status, required this.title, this.at, this.note});

  final OrderStatus status;
  final String title;
  final DateTime? at; // null: still to come
  final String? note;

  bool get done => at != null;
}

const _happyPath = [OrderStatus.confirmed, OrderStatus.packed, OrderStatus.shipped, OrderStatus.delivered];

String _title(OrderStatus s) => switch (s) {
      OrderStatus.pendingPayment => 'Order placed',
      OrderStatus.confirmed => 'Order confirmed',
      _ => s.label,
    };

/// `order_events` oldest first, then the happy-path steps still to come (none once cancelled/refunded).
/// A repeat of the previous status is a note event (admin note, "Refund processed"), so its note is the title.
List<TimelineStep> buildTimeline(Order o) {
  final steps = <TimelineStep>[];
  OrderStatus? prev;
  for (final e in o.events) {
    final repeat = e.status == prev && e.note != null;
    steps.add(TimelineStep(
      status: e.status,
      title: repeat ? e.note! : _title(e.status),
      at: e.createdAt,
      note: repeat ? null : e.note,
    ));
    prev = e.status;
  }
  if (o.status != OrderStatus.cancelled && o.status != OrderStatus.refunded) {
    for (final s in _happyPath.skip(_happyPath.indexOf(o.status) + 1)) {
      steps.add(TimelineStep(
        status: s,
        title: _title(s),
        note: s == OrderStatus.delivered ? 'Usually 2–4 days after shipping' : null,
      ));
    }
  }
  return steps;
}

/// Stand-in data for skeletons.
final placeholderOrder = Order(
  id: '',
  number: 'SM100000',
  status: OrderStatus.shipped,
  paymentMethod: PaymentMethod.razorpay,
  paymentStatus: PaymentStatus.paid,
  subtotalPaise: 7499900,
  deliveryFeePaise: 0,
  totalPaise: 7499900,
  address: const Address(
    name: 'Customer name',
    phone: '+919999999999',
    line1: 'House and street',
    city: 'City',
    state: 'State',
    pincode: '000000',
  ),
  createdAt: DateTime(2026),
  items: const [OrderItem(id: '', productName: 'Product name here', variantName: 'Variant name', unitPricePaise: 7499900, qty: 1)],
  events: [OrderEvent(status: OrderStatus.confirmed, createdAt: DateTime(2026))],
);
