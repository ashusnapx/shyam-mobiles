import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/env.dart';
import '../../../core/widgets/widgets.dart';

/// Public pages in site/ (Play Store and Razorpay need them as real URLs). Opened in a Custom Tab.
const _pages = [
  (PhosphorIconsRegular.info, 'About Shyam Mobiles', 'index.html'),
  (PhosphorIconsRegular.shieldCheck, 'Privacy policy', 'privacy.html'),
  (PhosphorIconsRegular.fileText, 'Terms of use', 'terms.html'),
  (PhosphorIconsRegular.arrowUUpLeft, 'Returns & refunds', 'refunds.html'),
  (PhosphorIconsRegular.truck, 'Shipping & delivery', 'shipping.html'),
  (PhosphorIconsRegular.chatCircle, 'Contact & grievances', 'contact.html'),
];

Future<void> openPolicy(BuildContext context, String page) async {
  final base = Env.policiesUrl.replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) {
    // shortcut: POLICIES_URL is unset until the pages are published; set it in env/*.json before release
    showMessage(context, 'Our policy pages go live before launch.');
    return;
  }
  final ok = await launchExternal(Uri.parse('$base/$page'), mode: LaunchMode.inAppBrowserView);
  if (!ok && context.mounted) showMessage(context, 'Couldn’t open the page. Check your connection and try again.');
}

class PolicyRows extends StatelessWidget {
  const PolicyRows({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final (icon, title, page) in _pages)
            ListTile(
              minTileHeight: 56,
              leading: Icon(icon),
              title: Text(title),
              trailing: const Icon(PhosphorIconsRegular.arrowUpRight, size: 18),
              onTap: () => openPolicy(context, page),
            ),
        ],
      );
}
