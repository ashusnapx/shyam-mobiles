import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/tokens.dart';

/// Our public pages (firebase/hosting, at POLICIES_URL; Play needs them as real URLs): route key → the app bar's
/// title. They open inside the app on `/policy/<key>` (PolicyScreen); 'about' is the site's home page.
const policyPages = {
  'about': 'About Shyam Mobiles',
  'privacy': 'Privacy policy',
  'terms': 'Terms of use',
  'refunds': 'Returns & refunds',
  'shipping': 'Shipping & delivery',
  'contact': 'Contact & grievances',
  'delete-account': 'Delete your account', // linked from the pages; the app has its own Delete account row
};

/// The page's path on the site: the clean URLs firebase.json serves.
String policyPath(String page) => page == 'about' ? '/' : '/$page';

/// The [policyPages] key for a path on our site, or null for any other page there.
String? policyPage(String path) {
  final page = path == '/' || path.isEmpty ? 'about' : path.substring(1);
  return policyPages.containsKey(page) ? page : null;
}

const _rows = [
  (PhosphorIconsRegular.info, 'about'),
  (PhosphorIconsRegular.shieldCheck, 'privacy'),
  (PhosphorIconsRegular.fileText, 'terms'),
  (PhosphorIconsRegular.arrowUUpLeft, 'refunds'),
  (PhosphorIconsRegular.truck, 'shipping'),
  (PhosphorIconsRegular.chatCircle, 'contact'),
];

void openPolicy(BuildContext context, String page) => context.push('/policy/$page');

class PolicyRows extends StatelessWidget {
  const PolicyRows({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final (icon, page) in _rows)
            ListTile(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              leading: Icon(icon),
              title: Text(policyPages[page]!),
              trailing: Icon(PhosphorIconsRegular.caretRight, size: IconSizes.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => openPolicy(context, page),
            ),
        ],
      );
}
