import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/google.dart';
import '../widgets/policies.dart';
import '../data/profile.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _deleting = false;

  Future<void> _signOut() async {
    await signOutOfGoogle();
    // gotrue clears the local session before calling the server, so a failed call still signs out here.
    await ref.read(supabaseProvider).auth.signOut().catchError((_) {});
  }

  Future<void> _deleteAccount() async {
    final c = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This removes your profile, saved addresses, cart and wishlist, and signs you out. '
          'Past orders stay on record for tax purposes but are no longer linked to you. '
          'This can’t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep account')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: c.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(supabaseProvider).functions.invoke('delete-account', body: const <String, dynamic>{});
      await _signOut(); // the user is gone server-side; this clears the local session
      if (!mounted) return;
      showMessage(context, 'Your account was deleted.');
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final c = Theme.of(context).colorScheme;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: Column(
          children: [
            const Expanded(
              child: SignInPrompt(
                icon: PhosphorIconsRegular.user,
                title: 'Sign in to your account',
                message: 'See your orders, saved addresses and wishlist.',
                from: '/account',
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm), child: _StoreCard()),
            const Padding(padding: EdgeInsets.only(bottom: Space.lg), child: PoliciesButton()),
          ],
        ),
      );
    }

    final profile = ref.watch(profileProvider);
    Widget row(IconData icon, String title, VoidCallback? onTap, {String? subtitle, Color? color, Widget? trailing}) =>
        ListTile(
          minTileHeight: 56,
          leading: Icon(icon, color: color),
          title: Text(title, style: color == null ? null : TextStyle(color: color)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? (color == null ? const Icon(PhosphorIconsRegular.caretRight, size: 18) : null),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([ref.refresh(profileProvider.future), ref.refresh(storeSettingsProvider.future)]),
        child: ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            _Header(
              name: profile.value?.fullName,
              loading: profile.isLoading && !profile.hasValue,
              contact: accountPhone(user.phone, profile.value?.phone) ?? user.email,
            ),
            const SizedBox(height: Space.sm),
            row(PhosphorIconsRegular.package, 'My orders', () => context.push('/orders')),
            row(PhosphorIconsRegular.heart, 'Wishlist', () => context.push('/wishlist')),
            row(PhosphorIconsRegular.mapPin, 'Addresses', () => context.push('/account/addresses')),
            row(PhosphorIconsRegular.userCircle, 'Profile', () => context.push('/account/profile')),
            const SectionHeader('Store'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: Space.lg), child: _StoreCard()),
            const SectionHeader('About & policies'),
            const PolicyRows(),
            const SizedBox(height: Space.sm),
            const Divider(),
            row(PhosphorIconsRegular.signOut, 'Sign out', _deleting ? null : _signOut, trailing: const SizedBox.shrink()),
            row(
              PhosphorIconsRegular.trash,
              'Delete account',
              _deleting ? null : _deleteAccount,
              color: c.error,
              trailing: _deleting
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.loading, required this.contact});

  final String? name;
  final bool loading;
  final String? contact;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final letters = initials(name);
    return InkWell(
      onTap: () => context.push('/account/profile'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
        child: Skeletonizer(
          enabled: loading,
          child: Row(
            spacing: Space.lg,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: c.primaryContainer,
                foregroundColor: c.onPrimaryContainer,
                child: letters == null
                    ? const Icon(PhosphorIconsRegular.user, size: 28)
                    : Text(letters, style: t.titleLarge?.copyWith(color: c.onPrimaryContainer)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? 'Your name' : name ?? 'Add your name',
                      style: t.titleLarge?.copyWith(color: name == null && !loading ? c.primary : null),
                    ),
                    if (contact != null)
                      Text(contact!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Store phone, WhatsApp, address and hours from `store_settings`. Shown signed in and out.
class _StoreCard extends ConsumerWidget {
  const _StoreCard();

  static const _placeholder = StoreSettings(
    deliveryFeePaise: 0,
    freeDeliveryMinPaise: 0,
    codEnabled: false,
    codMaxPaise: 0,
    storePhone: '+919999999999',
    storeAddress: 'Shop address goes here, City 000000',
    storeHours: '10 am – 9 pm',
    repairNote: '',
  );

  Future<void> _open(BuildContext context, Uri uri, String what) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) showMessage(context, 'Couldn’t open $what on this phone.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storeSettingsProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    if (settings.hasError && !settings.hasValue) {
      return Card(
        child: ListTile(
          leading: const Icon(PhosphorIconsRegular.cloudX),
          title: const Text('Couldn’t load store details'),
          subtitle: Text(friendlyError(settings.error!)),
          trailing: TextButton(onPressed: () => ref.invalidate(storeSettingsProvider), child: const Text('Retry')),
        ),
      );
    }
    final s = settings.value ?? _placeholder;
    final phone = s.storePhone;
    return Skeletonizer(
      enabled: !settings.hasValue,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
              child: Row(
                spacing: Space.md,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(size: 40),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shyam Mobiles', style: t.titleMedium),
                        if (s.storeAddress.isNotEmpty)
                          Text(s.storeAddress, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        if (s.storeHours.isNotEmpty)
                          Text('Open ${s.storeHours}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.phone),
              title: const Text('Call store'),
              subtitle: Text(displayPhone(phone)),
              onTap: () => _open(context, Uri(scheme: 'tel', path: phone), 'the dialler'),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.whatsappLogo),
              title: const Text('WhatsApp store'),
              onTap: () => _open(
                context,
                Uri.https('wa.me', '/${phone.replaceAll(RegExp(r'\D'), '')}', {'text': 'Hi, I need help with my account'}),
                'WhatsApp',
              ),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.shieldCheck),
              title: const Text('Returns & warranty'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + MediaQuery.paddingOf(context).bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.md,
                      children: [
                        Semantics(header: true, child: Text('Returns & warranty', style: t.titleLarge)),
                        Text(
                          s.returnsPolicy.isEmpty
                              ? 'Ask the store about returns and warranty for your phone.'
                              : s.returnsPolicy,
                          style: t.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}
