import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

/// The signed-in user's `profiles` row (own-row RLS). Null when signed out.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final row = await ref.watch(supabaseProvider).from('profiles').select().eq('id', uid).maybeSingle();
  return row == null ? null : Profile.fromJson(row);
});

/// Blank clears the name. Max 80 chars with a letter (DB check), tidied like every typed value.
Future<void> saveFullName(WidgetRef ref, String name) async {
  final trimmed = tidy(name);
  await ref
      .read(supabaseProvider)
      .from('profiles')
      .update({'full_name': trimmed.isEmpty ? null : trimmed}).eq('id', ref.read(currentUserIdProvider)!);
  ref.invalidate(profileProvider);
  await ref.read(profileProvider.future);
}

/// "Asha Kumari Rao" → "AR"; null when there's no name.
String? initials(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return null;
  return (words.first[0] + (words.length > 1 ? words.last[0] : '')).toUpperCase();
}

/// Supabase stores phones without '+'. "919876543210" → "+91 98765 43210".
String? accountPhone(String? authPhone, String? profilePhone) {
  final raw = (authPhone?.isNotEmpty ?? false) ? authPhone! : profilePhone;
  if (raw == null || raw.isEmpty) return null;
  return displayPhone(raw.startsWith('+') ? raw : '+$raw');
}
