import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/push.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/notifications.dart';

/// The kind's icon in a circle tinted by meaning, in the same tones as [Tag].
class NotificationIcon extends StatelessWidget {
  const NotificationIcon(this.kind, {super.key, this.size = 40});

  final String kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (icon, tone) = notificationStyle(kind);
    final (bg, fg) = switch (tone) {
      TagTone.info => (BrandColors.peacockMist, BrandColors.peacockInk),
      TagTone.ok => (c.secondaryContainer, c.onSecondaryContainer),
      TagTone.deal => (c.tertiaryContainer, c.onTertiaryContainer),
      TagTone.bad => (c.errorContainer, c.onErrorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: SizedBox.square(dimension: size, child: Icon(icon, size: size / 2, color: fg)),
    );
  }
}

/// The bell for Home and the admin dashboard: unread count in a gold badge that pops when it rises; opens
/// /notifications. Nothing when signed out.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  int _rises = 0; // Bump's trigger: only a rise pops it, not marking read

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentUserIdProvider) == null) return const SizedBox.shrink();
    ref.listen(unreadCountProvider, (prev, next) {
      if (prev != null && next > prev) setState(() => _rises++);
    });
    final n = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: n == 0 ? 'Notifications' : 'Notifications, $n unread',
      onPressed: () => context.push('/notifications'),
      icon: Bump(
        trigger: _rises,
        child: Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          child: const Icon(PhosphorIconsRegular.bell),
        ),
      ),
    );
  }
}

/// Kinds that follow a first order or repair booking: the moment to offer phone notifications.
const _askAfter = {'order_confirmed', 'order_awaiting_payment', 'repair_booked'};
const _askedKey = 'push_asked';

/// Wraps the whole app (MaterialApp.router's builder): slides the newest notification in at the top, one at a time,
/// for about 5 s (until closed, for screen-reader users), and keeps the unread poll running. Its first order or
/// booking is also when the app offers phone notifications, with a short explainer before Android's prompt.
class NotificationBannerHost extends ConsumerStatefulWidget {
  const NotificationBannerHost({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<NotificationBannerHost> createState() => _NotificationBannerHostState();
}

class _NotificationBannerHostState extends ConsumerState<NotificationBannerHost> {
  static const shown = Duration(seconds: 5);
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _arrived(AppNotification n) {
    _hide?.cancel();
    final banner = ref.read(notificationBannerProvider.notifier);
    // the list is on screen and refreshes itself
    if (widget.router.routerDelegate.currentConfiguration.uri.path == '/notifications') return banner.dismiss();
    final push = ref.read(pushServiceProvider);
    if (push.enabled && _askAfter.contains(n.kind)) unawaited(_maybeAsk(push));
    if (!MediaQuery.accessibleNavigationOf(context)) _hide = Timer(shown, banner.dismiss);
  }

  Future<void> _maybeAsk(PushService push) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true || await push.allowed()) return;
    await prefs.setBool(_askedKey, true); // asked once, whatever the answer
    await Future<void>.delayed(const Duration(milliseconds: 1200)); // let the order or booking screen land first
    final context = widget.router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final yes = await confirmChoice(
      context,
      title: 'Get updates on your phone?',
      message: 'We’ll tell you when your order is packed and on its way, when your repair is ready, and when a '
          'quote needs your OK. Nothing else.',
      action: 'Turn on',
      keep: 'Not now',
    );
    if (yes) await push.ask().catchError((Object _) => false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(unreadCountProvider); // the poll lives as long as the app
    ref.listen(notificationBannerProvider, (_, n) {
      if (n != null) _arrived(n);
    });
    final n = ref.watch(notificationBannerProvider);
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSwitcher(
            duration: still ? Duration.zero : Motion.normal,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) => SlideTransition(
              position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: n == null
                ? const SizedBox.shrink(key: ValueKey('none'))
                : _Banner(
                    key: ValueKey('${n.id}${n.title}'),
                    n: n,
                    onOpen: () {
                      _hide?.cancel();
                      ref.read(notificationBannerProvider.notifier).dismiss();
                      unawaited(ref.read(unreadCountProvider.notifier).open(widget.router, n));
                    },
                    onClose: () {
                      _hide?.cancel();
                      ref.read(notificationBannerProvider.notifier).dismiss();
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.n, required this.onOpen, required this.onClose});

  final AppNotification n;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Material(
            color: c.surface,
            elevation: 6,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(Radii.lg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, 0, Space.sm),
                child: Row(
                  children: [
                    NotificationIcon(n.kind, size: 36),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          if (n.body.isNotEmpty)
                            Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    TextButton(onPressed: onOpen, child: const Text('View')),
                    // a label, not a tooltip: the banner sits above the Navigator, outside any Overlay
                    Semantics(
                      button: true,
                      label: 'Dismiss',
                      excludeSemantics: true,
                      child: IconButton(onPressed: onClose, icon: const Icon(PhosphorIconsRegular.x, size: 18)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
