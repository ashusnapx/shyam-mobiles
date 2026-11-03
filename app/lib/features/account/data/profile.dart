import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'profile_repository.dart';

/// The signed-in user's profile. Null when signed out.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return ref.watch(profileRepositoryProvider).profile(uid);
});

/// Blank clears the name. Tidied like every typed value; the caller checked it (validatePersonName).
Future<void> saveFullName(WidgetRef ref, String name) async {
  await ref.read(profileRepositoryProvider).saveFullName(ref.read(currentUserIdProvider)!, tidy(name));
  ref.invalidate(profileProvider);
  await ref.read(profileProvider.future);
}

final _nameChars = RegExp(r"^[\p{L}\p{M} .'-]+$", unicode: true);

/// The name asked at sign-up and in Profile: 2 to 60 characters, letters (any script) and spaces. Dots, apostrophes and
/// hyphens are fine too ("R.K. Sharma", "D'Souza").
String? validatePersonName(String? v) {
  final s = tidy(v);
  if (s.isEmpty) return 'Enter your name.';
  if (!_nameChars.hasMatch(s)) return 'Use letters only, like Ravi Kumar.';
  if (hasLetter.allMatches(s).length < 2) return 'Enter at least 2 letters.';
  if (s.runes.length > 60) return 'Keep it to 60 characters.';
  return null;
}

/// How a typed name is saved and shown: tidied, each word capitalised. "ravi kumar" and "RAVI KUMAR" → "Ravi Kumar";
/// a name typed in mixed case keeps it ("McDonald").
String displayName(String name) {
  final s = tidy(name);
  final oneCase = s == s.toLowerCase() || s == s.toUpperCase();
  return s
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + (oneCase ? w.substring(1).toLowerCase() : w.substring(1)))
      .join(' ');
}

/// "ravi kumar" → "Ravi"; null with no name. Greetings and WhatsApp messages use it, never the email. Words that don't
/// start with a letter ("(staff)") are skipped.
String? firstName(String? name) {
  final letter = RegExp(r'^\p{L}', unicode: true);
  final first = tidy(name).split(' ').where(letter.hasMatch).firstOrNull;
  return first == null ? null : displayName(first);
}

/// "Asha Kumari Rao" → "AR"; null when there's no name. Words that don't start with a letter ("(staff)") are skipped.
String? initials(String? name) {
  final letter = RegExp(r'^\p{L}', unicode: true);
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where(letter.hasMatch).toList();
  if (words.isEmpty) return null;
  return (words.first[0] + (words.length > 1 ? words.last[0] : '')).toUpperCase();
}

/// Supabase stores phones without '+'. "919876543210" → "+91 98765 43210".
String? accountPhone(String? authPhone, String? profilePhone) {
  final raw = (authPhone?.isNotEmpty ?? false) ? authPhone! : profilePhone;
  if (raw == null || raw.isEmpty) return null;
  return displayPhone(raw.startsWith('+') ? raw : '+$raw');
}
