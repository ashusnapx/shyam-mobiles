import 'package:cloud_firestore/cloud_firestore.dart';

/// A Firestore doc or callable reply (camelCase, Timestamps) as the snake_case JSON the models parse, so one
/// fromJson serves both backends until Phase 2: `{'minSubtotalPaise': 1, 'endsAt': Timestamp}` →
/// `{'min_subtotal_paise': 1, 'ends_at': '2026-…'}`.
Object? snake(Object? v) => switch (v) {
      Timestamp t => t.toDate().toIso8601String(),
      Map m => {for (final e in m.entries) _key(e.key as String): snake(e.value)},
      List l => [for (final x in l) snake(x)],
      _ => v,
    };

String _key(String k) => k.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

Map<String, dynamic> snakeMap(Map<String, dynamic> m, [String? id]) => {...snake(m) as Map<String, dynamic>, 'id': ?id};

/// The other way, for payloads built in today's snake_case (Promotion.toJson, the banner form): keys only.
Map<String, dynamic> camelMap(Map<String, Object?> m) =>
    {for (final e in m.entries) e.key.replaceAllMapped(RegExp('_([a-z])'), (x) => x[1]!.toUpperCase()): e.value};
