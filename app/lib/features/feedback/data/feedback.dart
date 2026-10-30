import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/paging.dart';
import '../../../core/supabase.dart';

// Feedback (docs/SPEC.md `send_feedback`): a rating, a comment or both, about an order, a repair, a product listing,
// a bug, or anything. Customers write only through the RPC and read their own rows; staff read all and track each
// one new → seen → resolved with a note.

enum FeedbackKind {
  general('General'),
  order('Order'),
  repair('Repair'),
  product('Product listing'),
  bug('Problem in the app');

  const FeedbackKind(this.label);
  final String label;
}

enum FeedbackStatus {
  unread('new', 'New'),
  seen('seen', 'Seen'),
  resolved('resolved', 'Resolved');

  const FeedbackStatus(this.value, this.label);
  final String value;
  final String label;

  static FeedbackStatus parse(String v) => values.firstWhere((s) => s.value == v);
}

const maxFeedbackMessage = 1000; // feedback.message
const maxFeedbackNote = 500; // feedback.admin_note

/// The route the feedback was sent from, as `feedback.screen` allows: ≤ 200 of `/A-Za-z0-9_?=&.%-`, from a `/`.
String? feedbackScreen(Uri? uri) {
  if (uri == null) return null;
  final s = uri.toString().replaceAll(RegExp(r'[^A-Za-z0-9/_?=&.%-]'), '');
  if (!s.startsWith('/')) return null;
  return s.length <= 200 ? s : s.substring(0, 200);
}

/// One `feedback` row with what it's about, for the customer's own card and the staff inbox.
class FeedbackEntry {
  const FeedbackEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.rating,
    this.message = '',
    this.orderId,
    this.repairId,
    this.productId,
    this.screen,
    this.adminNote,
    this.orderNumber,
    this.repairNumber,
    this.productName,
    this.customerName,
    this.customerPhone,
  });

  final String id;
  final FeedbackKind kind;
  final int? rating;
  final String message;
  final String? orderId;
  final String? repairId;
  final String? productId;
  final String? screen;
  final FeedbackStatus status;
  final String? adminNote;
  final DateTime createdAt;
  final String? orderNumber;
  final String? repairNumber;
  final String? productName;
  // Staff can't read profiles: the name and phone come from the order's address or the repair's contact number.
  final String? customerName;
  final String? customerPhone;

  factory FeedbackEntry.fromJson(Map<String, dynamic> j) {
    final order = j['order'] as Map<String, dynamic>?;
    final repair = j['repair'] as Map<String, dynamic>?;
    final address = order?['address'] as Map<String, dynamic>?;
    return FeedbackEntry(
      id: j['id'],
      kind: FeedbackKind.values.byName(j['kind']),
      rating: j['rating'],
      message: j['message'] ?? '',
      orderId: j['order_id'],
      repairId: j['repair_id'],
      productId: j['product_id'],
      screen: j['screen'],
      status: FeedbackStatus.parse(j['status']),
      adminNote: j['admin_note'],
      createdAt: DateTime.parse(j['created_at']),
      orderNumber: order?['number'],
      repairNumber: repair?['number'],
      productName: (j['product'] as Map<String, dynamic>?)?['name'],
      customerName: address?['name'],
      customerPhone: address?['phone'] ?? repair?['contact_phone'],
    );
  }
}

const _select = '*, order:orders(number, address), repair:repair_bookings(number, contact_phone), product:products(name)';

typedef FeedbackFilter = ({FeedbackStatus? status, FeedbackKind? kind, String? productId});

/// Feedback reads and writes; a provider so tests can swap it.
class FeedbackApi {
  const FeedbackApi(this._db);

  final SupabaseClient _db;

  /// `send_feedback`. Rating an order or a repair again replaces the earlier rating. Returns the row id.
  Future<String> send({
    required FeedbackKind kind,
    int? rating,
    String message = '',
    String? orderId,
    String? repairId,
    String? productId,
    String? screen,
  }) async =>
      await _db.rpc<String>('send_feedback', params: {
        'p_kind': kind.name,
        'p_rating': rating,
        'p_message': message,
        'p_order_id': orderId,
        'p_repair_id': repairId,
        'p_product_id': productId,
        'p_screen': screen,
      });

  /// The signed-in customer's rating of an order or a repair, if they gave one. Filtered on user_id: staff read all.
  Future<FeedbackEntry?> mine(String userId, FeedbackKind kind, String id) async {
    final row = await _db
        .from('feedback')
        .select()
        .eq('user_id', userId)
        .eq('kind', kind.name)
        .eq(kind == FeedbackKind.order ? 'order_id' : 'repair_id', id)
        .maybeSingle();
    return row == null ? null : FeedbackEntry.fromJson(row);
  }

  /// Staff: newest first, rows [from]..[from + size - 1].
  Future<List<FeedbackEntry>> inbox(FeedbackFilter f, int from, int size) async {
    var q = _db.from('feedback').select(_select);
    if (f.status != null) q = q.eq('status', f.status!.value);
    if (f.kind != null) q = q.eq('kind', f.kind!.name);
    if (f.productId != null) q = q.eq('product_id', f.productId!);
    final rows = await q.order('created_at', ascending: false).order('id').range(from, from + size - 1);
    return [for (final r in rows) FeedbackEntry.fromJson(r)];
  }

  Future<FeedbackEntry> entry(String id) async =>
      FeedbackEntry.fromJson(await _db.from('feedback').select(_select).eq('id', id).single());

  /// Staff may change only these two columns.
  Future<void> update(String id, {FeedbackStatus? status, String? adminNote}) async {
    await _db
        .from('feedback')
        .update({'status': ?status?.value, 'admin_note': ?adminNote})
        .eq('id', id)
        .select('id')
        .single();
  }

  Future<int> newCount() async => (await _db.from('feedback').select('id').eq('status', 'new').count(CountOption.exact)).count;

  /// Staff: reports about one product listing (kind product), any status.
  Future<int> listingReports(String productId) async => (await _db
          .from('feedback')
          .select('id')
          .eq('kind', FeedbackKind.product.name)
          .eq('product_id', productId)
          .count(CountOption.exact))
      .count;
}

final feedbackApiProvider = Provider<FeedbackApi>((ref) => FeedbackApi(ref.watch(supabaseProvider)));

/// The customer's own rating of an order or a repair (null: not rated yet).
final myFeedbackProvider = FutureProvider.autoDispose.family<FeedbackEntry?, (FeedbackKind, String)>((ref, key) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return ref.watch(feedbackApiProvider).mine(uid, key.$1, key.$2);
});

/// Staff inbox, a page at a time.
final adminFeedbackProvider =
    AsyncNotifierProvider.autoDispose.family<AdminFeedback, Paged<FeedbackEntry>, FeedbackFilter>(AdminFeedback.new);

class AdminFeedback extends PagedNotifier<FeedbackEntry> {
  AdminFeedback(this.filter);

  final FeedbackFilter filter;

  @override
  Object idOf(FeedbackEntry e) => e.id;

  @override
  Future<List<FeedbackEntry>> fetch(int from, int size) => ref.read(feedbackApiProvider).inbox(filter, from, size);
}

final adminFeedbackEntryProvider =
    FutureProvider.autoDispose.family<FeedbackEntry, String>((ref, id) => ref.watch(feedbackApiProvider).entry(id));

/// For the admin product editor's "Reports about this listing".
final listingReportsProvider = FutureProvider.autoDispose
    .family<int, String>((ref, productId) => ref.watch(feedbackApiProvider).listingReports(productId));

/// For the dashboard tile.
final feedbackNewCountProvider = FutureProvider.autoDispose<int>((ref) => ref.watch(feedbackApiProvider).newCount());
