import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'catalog_index.dart';

/// The sharded catalog index (functions/src/catalog/shard.ts, docs/FIREBASE.md D3): `catalogIndex/<kind>_manifest`
/// lists the chunks (`<kind>_<category>_<n>`) with their versions. A chunk is downloaded only when its version is not
/// already held, in memory or in Firestore's on-device cache, so a change to one product re-downloads one chunk.
class ChunkedIndex {
  /// [live]: the manifest is a snapshot listener (customers, so a change shows at once); otherwise it is read on every
  /// [read] (staff want the latest stock).
  ChunkedIndex(this._db, this._kind, {required this.live});

  final FirebaseFirestore _db;
  final String _kind;
  final bool live;
  final Map<String, ({int v, IndexCards cards})> _have = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Completer<Map<String, ({int v, String c})>>? _first;
  Map<String, ({int v, String c})> _manifest = const {};
  String? _allSig;
  IndexCards _all = const {};

  Map<String, ({int v, String c})> _parse(Map<String, dynamic>? d) => {
        for (final MapEntry(:key, :value) in ((d?['chunks'] as Map?) ?? const {}).entries)
          key as String: (v: (value['v'] as num).toInt(), c: value['c'] as String),
      };

  /// A failed first load is retried on the next call.
  Future<Map<String, ({int v, String c})>> _manifestNow() async {
    final ref = _db.doc('catalogIndex/${_kind}_manifest');
    if (!live) return _parse((await ref.get()).data());
    if (_first == null) {
      final first = _first = Completer();
      _sub = ref.snapshots().listen((s) {
        _manifest = _parse(s.data());
        if (!first.isCompleted) first.complete(_manifest);
      }, onError: (Object e) {
        if (first.isCompleted) return;
        first.completeError(e);
        _sub?.cancel();
        _first = null;
      });
    }
    await _first!.future;
    return _manifest;
  }

  Future<IndexCards> _chunk(String id, int v) async {
    final held = _have[id];
    if (held != null && held.v == v) return held.cards;
    final ref = _db.doc('catalogIndex/$id');
    IndexCards? cards;
    try {
      final c = await ref.get(const GetOptions(source: Source.cache));
      if ((c.data()?['v'] as num?)?.toInt() == v) cards = indexCards(c.data());
    } catch (_) {} // not cached yet
    cards ??= indexCards((await ref.get()).data());
    _have[id] = (v: v, cards: cards);
    return cards;
  }

  /// The cards of [category]'s chunks, or of every chunk.
  Future<IndexCards> read({String? category}) async {
    final m = await _manifestNow();
    _have.removeWhere((id, _) => !m.containsKey(id));
    final ids = [for (final e in m.entries) if (category == null || e.value.c == category) e.key]..sort();
    final sig = category == null ? [for (final id in ids) '$id:${m[id]!.v}'].join(',') : null;
    if (sig != null && sig == _allSig) return _all;
    final parts = await Future.wait([for (final id in ids) _chunk(id, m[id]!.v)]);
    final merged = <String, Map<String, dynamic>>{for (final p in parts) ...p};
    if (sig != null) {
      _allSig = sig;
      _all = merged;
    }
    return merged;
  }
}
