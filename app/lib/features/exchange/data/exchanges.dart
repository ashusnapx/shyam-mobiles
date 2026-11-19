import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase.dart' show currentUserIdProvider;
import 'exchange_repository.dart';

/// The signed-in customer's exchange requests, newest first.
final myExchangesProvider = FutureProvider.autoDispose<List<ExchangeRequest>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  return uid == null ? const [] : ref.watch(exchangeRepositoryProvider).mine(uid);
});

/// Staff: the newest 50.
final adminExchangesProvider = FutureProvider.autoDispose<List<ExchangeRequest>>((ref) => ref.watch(exchangeRepositoryProvider).recent());
