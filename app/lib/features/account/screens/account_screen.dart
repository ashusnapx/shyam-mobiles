import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/google.dart';
import '../../feedback/data/feedback.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../notifications/data/notifications.dart';
import '../widgets/policies.dart';
import '../widgets/store_card.dart';
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

  // Signing back in costs a new code (an SMS for phone users), so a stray tap shouldn't sign anyone out.
  Future<void> _confirmSignOut() async {
    final ok = await confirmChoice(
      context,
      title: 'Sign out?',
      message: 'Your cart, wishlist and orders stay saved to your account. You’ll need a new code to sign in again.',
      action: 'Sign out',
      keep: 'Stay signed in',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _signOut();
    if (mounted) showMessage(context, 'You’re signed out.');
  }

  Future<void> _deleteAccount() async {
    final ok = await confirmChoice(
      context,
      title: 'Delete your account?',
      message: 'This removes your profile, saved addresses, cart and wishlist, and signs you out. '
          'Past orders stay on record for tax purposes but are no longer linked to you. '
          'This can’t be undone.',
      action: 'Delete account',
      keep: 'Keep account',
      destructive: true,
    );
    if (!ok || !mounted) return;
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
        // one scrolling list, sign-in first: squeezed into what the store card left over, the prompt scrolled its
        // own button out of sight on shorter phones
        body: ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: const [
            SignInPrompt(
              icon: PhosphorIconsRegular.user,
              tone: Worlds.account,
              title: 'Sign in to your account',
              message: 'See your orders, saved addresses and wishlist.',
              from: '/account',
            ),
            SectionHeader('Shop', gutter: Space.gutter),
            Padding(padding: EdgeInsets.symmetric(horizontal: Space.gutter), child: StoreCard()),
            SectionHeader('About & policies', gutter: Space.gutter),
            PolicyRows(),
          ],
        ),
      );
    }

    final profile = ref.watch(profileProvider);
    // each row's icon on its own colour, so the menu reads at a glance; a destructive row ([color]) has no well
    Widget row(IconData icon, String title, VoidCallback? onTap,
            {Tint? tint, String? subtitle, Color? color, Widget? trailing}) =>
        ListTile(
          minTileHeight: subtitle == null ? 56 : 64,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          leading: tint == null ? Icon(icon, color: color) : IconWell(icon, tint: tint),
          title: Text(title, style: color == null ? null : TextStyle(color: color)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ??
              (color == null ? Icon(PhosphorIconsRegular.caretRight, size: IconSizes.sm, color: c.onSurfaceVariant) : null),
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
              // the phone, never the email: that is how the shop knows its customers
              contact: accountPhone(user.phone, profile.value?.phone),
            ),
            const SizedBox(height: Space.sm),
            row(PhosphorIconsRegular.package, 'My orders', () => context.push('/orders'), tint: Worlds.shop),
            row(PhosphorIconsRegular.heart, 'Wishlist', () => context.push('/wishlist'), tint: Worlds.account),
            row(PhosphorIconsRegular.sealPercent, 'Offers & coupons', () => context.push('/offers'), tint: Worlds.offers),
            if (ref.watch(storeSettingsProvider).value case final s? when s.referralEnabled)
              row(PhosphorIconsRegular.gift, 'Refer & earn', () => context.push('/account/refer'),
                  tint: Worlds.cart,
                  subtitle: 'Give ${formatInr(s.referralFriendPaise)}, get ${formatInr(s.referralRewardPaise)}'),
            row(PhosphorIconsRegular.mapPin, 'Addresses', () => context.push('/account/addresses'), tint: Worlds.search),
            // the bell on Home already leads here, so it sits lower
            row(PhosphorIconsRegular.bell, 'Notifications', () => context.push('/notifications'),
                tint: Worlds.admin,
                subtitle: switch (ref.watch(unreadCountProvider)) { 0 => null, final n => '$n unread' }),
            row(PhosphorIconsRegular.userCircle, 'Profile', () => context.push('/account/profile'),
                tint: (BrandColors.slateMist, BrandColors.slate)),
            row(
              PhosphorIconsRegular.chatCircleText,
              'Send feedback',
              tint: (BrandColors.violetMist, BrandColors.violet),
              () => showFeedbackSheet(
                context,
                title: 'Send feedback',
                kinds: const [FeedbackKind.general, FeedbackKind.bug],
                hint: 'What’s on your mind?',
              ),
              subtitle: 'An idea, or something not working',
            ),
            const SectionHeader('Shop', gutter: Space.gutter),
            const Padding(padding: EdgeInsets.symmetric(horizontal: Space.gutter), child: StoreCard()),
            const SectionHeader('About & policies', gutter: Space.gutter),
            const PolicyRows(),
            const SizedBox(height: Space.sm),
            const Divider(),
            row(PhosphorIconsRegular.signOut, 'Sign out', _deleting ? null : _confirmSignOut,
                tint: (c.surfaceContainer, c.onSurface), trailing: const SizedBox.shrink()),
            row(
              PhosphorIconsRegular.trash,
              'Delete account',
              _deleting ? null : _deleteAccount,
              color: c.error,
              trailing: _deleting ? const ButtonSpinner() : null,
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
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.lg),
        child: Skeletonizer(
          enabled: loading,
          child: Row(
            spacing: Space.lg,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Worlds.account.$1,
                foregroundColor: Worlds.account.$2,
                child: letters == null
                    ? const Icon(PhosphorIconsRegular.user, size: 28)
                    : Text(letters, style: t.titleLarge?.copyWith(color: Worlds.account.$2)),
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
