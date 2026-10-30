import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/env.dart';
import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/widgets/store_links.dart';
import '../data/offers.dart';
import '../widgets/offer_widgets.dart';

/// The WhatsApp message a customer forwards: the code, what the friend gets, and the link that carries the code into
/// the app (the same text as the Share button). No contact is picked here.
Uri referralShareUri(Referral r, {String host = Env.linkHost}) => Uri.https('wa.me', '/', {
      'text': shareText('I shop for phones at Shyam Mobiles.', link: shareLink(code: r.code, host: host), referral: r),
    });

const _placeholder = Referral(enabled: true, code: 'ABCD1234', friendPaise: 20000, rewardPaise: 20000, minOrderPaise: 199900);

class ReferScreen extends ConsumerWidget {
  const ReferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referral = ref.watch(myReferralProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Refer & earn'), actions: [
        if (referral.value?.enabled ?? false) const ShareButton(what: 'I shop for phones at Shyam Mobiles.'),
      ]),
      body: AsyncBody<Referral>(
        value: referral,
        onRetry: () => ref.invalidate(myReferralProvider),
        loading: const Skeletonizer(child: _Body(referral: _placeholder)),
        data: (r) => r.enabled
            ? RefreshIndicator(
                onRefresh: () => ref.refresh(myReferralProvider.future),
                child: _Body(referral: r, monthlyCap: ref.watch(storeSettingsProvider).value?.referralMonthlyCap),
              )
            : EmptyState(
                icon: PhosphorIconsRegular.gift,
                title: 'Refer & earn isn’t running right now',
                message: 'Check Offers for today’s coupons and sales.',
                action: FilledButton(onPressed: () => context.pushReplacement('/offers'), child: const Text('See offers')),
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.referral, this.monthlyCap});

  final Referral referral;
  final int? monthlyCap; // store_settings.referral_monthly_cap: rewards per IST month, the rest are void

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final r = referral;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: heroGradients[0]),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(PhosphorIconsFill.gift, color: BrandColors.gold, size: 32),
                  const SizedBox(height: Space.sm),
                  Semantics(
                    header: true,
                    child: Text(
                      'Give ${formatInr(r.friendPaise)}, get ${formatInr(r.rewardPaise)}',
                      style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Your friend gets ${formatInr(r.friendPaise)} off their first order of ${formatInr(r.minOrderPaise)} '
                    'or more. You get a ${formatInr(r.rewardPaise)} coupon when an order of theirs of '
                    '${formatInr(r.minOrderPaise)} or more is delivered.',
                    style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ),
        ).enter(context),
        const SizedBox(height: Space.lg),
        Text('Your code', style: t.titleSmall),
        const SizedBox(height: Space.sm),
        CodeActions(code: r.code),
        const SizedBox(height: Space.md),
        FilledButton.icon(
          onPressed: () => openExternal(context, referralShareUri(r), 'Couldn’t open WhatsApp.'),
          icon: const WhatsAppIcon(size: 20),
          label: const Text('Share on WhatsApp'),
        ),
        const SizedBox(height: Space.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Row(
              children: [
                for (final (n, label) in [(r.joined, 'Friends joined'), (r.rewarded, 'Rewards earned')])
                  Expanded(
                    child: Semantics(
                      container: true,
                      label: '$label: $n',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          Text('$n', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(label, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          [
            'Your coupon is for an order of ${formatInr(r.minOrderPaise)} or more and lasts 90 days. It shows up in '
                'Offers & coupons.',
            if (monthlyCap case final cap? when cap > 0)
              'You can earn up to $cap reward${cap == 1 ? '' : 's'} a month. Friends who join after that still get '
                  'their discount, but no reward is added for you.',
          ].join(' '),
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        if (r.canEnterCode) const _FriendCode(),
      ],
    );
  }
}

/// "Have a friend's code?": shown only until the customer has a referrer or an order.
class _FriendCode extends ConsumerStatefulWidget {
  const _FriendCode();

  @override
  ConsumerState<_FriendCode> createState() => _FriendCodeState();
}

class _FriendCodeState extends ConsumerState<_FriendCode> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_busy) return;
    final invalid = validateCode(_code.text, min: 6, max: 10);
    if (invalid != null) return setState(() => _error = invalid);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final welcome = await applyReferralCode(ref, _code.text.trim());
      if (mounted) showMessage(context, 'Done. Use ${welcome.code} for ${offerHeadline(welcome)}. It’s in Offers & coupons.');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.xl),
        Semantics(header: true, child: Text('Have a friend’s code?', style: t.titleMedium)),
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                decoration: InputDecoration(labelText: 'Friend’s code', errorText: _error, errorMaxLines: 3),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: couponCodeInput,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: FilledButton(
                onPressed: _busy ? null : _apply,
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Apply'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
