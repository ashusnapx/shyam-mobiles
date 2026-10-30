import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../features/offers/data/offers.dart';
import 'env.dart';
import 'format.dart';
import 'models/models.dart';
import 'supabase.dart';
import 'widgets/widgets.dart';

final _slug = RegExp(r'^[a-z0-9-]{1,160}$');
final _offerId = RegExp(r'^[0-9a-f-]{36}$');
final _code = RegExp(r'^[A-Z0-9]{6,10}$');

/// `https://<LINK_HOST>/open?p=<product slug>&ref=<code>` (an offer: `o=<offer id>`; just a referral: `ref=`).
/// site/open.html serves it when the app isn't installed. Null without a LINK_HOST: shares then go without a link.
Uri? shareLink({String? product, String? offer, String? code, String host = Env.linkHost}) => host.isEmpty
    ? null
    : Uri.https(host, '/open', {'p': ?product, 'o': ?offer, 'ref': ?code});

/// What the share sheet sends: [what] ("Samsung Galaxy S25 · ₹74,999 at Shyam Mobiles"), the sharer's code and
/// what it's worth, then the link (WhatsApp previews the last link), or how to get the app when there's none.
String shareText(String what, {Uri? link, Referral? referral}) {
  final code = referral == null
      ? null
      : 'Use my code ${referral.code} for ${formatInr(referral.friendPaise)} off your first order of '
          '${formatInr(referral.minOrderPaise)} or more.';
  return [what, ?code, link?.toString() ?? 'Get the Shyam Mobiles app on Google Play.'].join('\n');
}

typedef OpenLink = ({String to, String? code});

/// Where a shared link leads and the friend's code it carries: `/open?p=&o=&ref=` (the https App Link, or the
/// install referrer replayed in-app) and `shyammobiles://open?…`. Null for any other address. Values that aren't a
/// slug, an offer id or a code are dropped, so a link can only ever open a product, an offer or Home.
OpenLink? openLink(Uri uri) {
  if (uri.path != '/open' && !(uri.scheme == 'shyammobiles' && uri.host == 'open')) return null;
  final q = uri.queryParameters;
  final p = q['p'] ?? '', o = q['o'] ?? '', code = (q['ref'] ?? '').toUpperCase();
  return (
    to: _slug.hasMatch(p) ? '/product/$p' : (_offerId.hasMatch(o) ? '/offers/$o' : '/'),
    code: _code.hasMatch(code) ? code : null,
  );
}

/// The snackbar once a friend's code from a link is applied: the welcome coupon `apply_referral_code` returns.
String friendCodeMessage(Offer welcome) => 'Your friend’s code is in: ${formatInr(welcome.value)} off your first '
    'order of ${formatInr(welcome.minSubtotalPaise)} or more';

/// App-bar Share: the system share sheet with [what], a link to [product] or [offer] (or the app), and the sharer's
/// referral code when they're signed in and Refer & earn is on.
class ShareButton extends ConsumerStatefulWidget {
  const ShareButton({super.key, required this.what, this.product, this.offer, this.style});

  final String what;
  final String? product; // slug
  final String? offer; // id
  final ButtonStyle? style;

  @override
  ConsumerState<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends ConsumerState<ShareButton> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      Referral? referral;
      if (ref.read(currentUserIdProvider) != null) {
        try {
          // a slow network shares without the code rather than keep the sheet waiting
          final mine = await ref.read(offersApiProvider).myReferral().timeout(const Duration(seconds: 4));
          if (mine.enabled) referral = mine;
        } catch (_) {}
      }
      final link = shareLink(product: widget.product, offer: widget.offer, code: referral?.code);
      await SharePlus.instance.share(ShareParams(text: shareText(widget.what, link: link, referral: referral)));
    } catch (_) {
      if (mounted) showMessage(context, 'Couldn’t open sharing. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Share',
        style: widget.style,
        onPressed: _busy ? null : _share,
        icon: _busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(PhosphorIconsRegular.shareNetwork, size: 20),
      );
}
