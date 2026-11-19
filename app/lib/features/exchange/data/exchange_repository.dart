import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider, functionsProvider, storageProvider;
import '../../admin/data/photos.dart' show PreparedPhoto;
import 'exchange_repository_firebase.dart';
import 'exchange_repository_supabase.dart';

enum ExchangeAge {
  under1('under_1', 'Under 1 year'),
  y1to2('1_2', '1–2 years'),
  y2to3('2_3', '2–3 years'),
  over3('over_3', 'Over 3 years');

  const ExchangeAge(this.value, this.label);
  final String value;
  final String label;
  static ExchangeAge parse(String? v) => values.firstWhere((a) => a.value == v, orElse: () => over3);
}

enum ExchangeCondition {
  likeNew('like_new', 'Like new', 'No scratches, everything works'),
  good('good', 'Good', 'Light scratches, everything works'),
  fair('fair', 'Fair', 'Visible wear, or a weak battery'),
  damaged('damaged', 'Damaged', 'Cracked, or something doesn’t work');

  const ExchangeCondition(this.value, this.label, this.hint);
  final String value;
  final String label;
  final String hint;
  static ExchangeCondition parse(String? v) => values.firstWhere((c) => c.value == v, orElse: () => damaged);
}

/// An "Exchange your old phone" request (firebase/functions/src/model/exchanges.ts). No price exists until staff give
/// an estimate, and an estimate is a range the shop confirms when it checks the phone (docs/GROWTH.md §2c).
class ExchangeRequest {
  const ExchangeRequest({
    required this.id,
    required this.brand,
    required this.model,
    required this.age,
    required this.condition,
    this.photos = const [],
    this.lowPaise,
    this.highPaise,
    this.note = '',
    required this.createdAt,
  });

  final String id;
  final String brand;
  final String model;
  final ExchangeAge age;
  final ExchangeCondition condition;
  final List<String> photos; // Storage keys under exchange-photos/ (the customer and staff only)
  final int? lowPaise; // null until the shop estimates
  final int? highPaise;
  final String note;
  final DateTime createdAt;

  bool get estimated => lowPaise != null && highPaise != null;
}

/// Exchange requests (docs/GROWTH.md §2c). The Supabase build has no server side: [enabled] is false and only the
/// WhatsApp message works there.
abstract interface class ExchangeRepository {
  bool get enabled;

  /// Saves the request; returns its id. RATE_LIMITED past 5 a day.
  Future<String> request({
    required String brand,
    required String model,
    required ExchangeAge age,
    required ExchangeCondition condition,
    List<String> photos = const [],
    String? forProductId,
  });

  /// Uploads `exchange-photos/<uid>/<millis>.webp` and its thumb; returns the full photo's key.
  Future<String> uploadPhoto(String uid, PreparedPhoto photo);

  /// The customer's own requests, newest first.
  Future<List<ExchangeRequest>> mine(String uid);

  /// A private exchange photo's bytes (its thumb when there is one). Bytes, not a download URL: a URL's token would
  /// outlive the Rules check (Storage Rules: the customer and staff).
  Future<Uint8List?> photo(String key);

  // Staff ------------------------------------------------------------------------------------------------------

  /// Every request, newest first.
  Future<List<ExchangeRequest>> recent({int limit = 50});

  /// The estimate range (low ≤ high) and a short note; the customer is notified.
  Future<void> estimate(String id, {required int lowPaise, required int highPaise, String note = ''});
}

final exchangeRepositoryProvider = Provider<ExchangeRepository>((ref) => backend == Backend.firebase
    ? FirebaseExchangeRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider), ref.watch(storageProvider))
    : const SupabaseExchangeRepository());
