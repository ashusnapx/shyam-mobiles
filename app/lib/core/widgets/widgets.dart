import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import 'package:url_launcher/url_launcher.dart';

import '../errors.dart';
import '../format.dart';
import '../network.dart';
import '../supabase.dart';
import '../theme/tokens.dart';

/// Product photo from the `product-images` bucket on a soft tinted well, with an icon when there's no photo.
/// In data-saver mode it loads the 480 px thumb (the gallery's full-screen viewer loads the full photo).
class ProductImage extends StatelessWidget {
  const ProductImage(
    this.path, {
    super.key,
    this.aspectRatio = 1,
    this.radius = Radii.lg,
    this.padding = Space.md,
    this.fit = BoxFit.contain,
    this.color,
  });

  final String? path;
  final double aspectRatio;
  final double radius;
  final double padding;
  final BoxFit fit; // cover for shop photos; clip the parent to round its corners
  final Color? color; // the well; the product gallery is white

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fallback = Center(
      child: Icon(PhosphorIconsLight.deviceMobile, size: 40, color: c.onSurfaceVariant.withValues(alpha: 0.5)),
    );
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color ?? c.surfaceContainer, borderRadius: BorderRadius.circular(radius)),
        child: path == null
            ? fallback
            : Padding(
                padding: EdgeInsets.all(padding),
                child: _NetworkPhoto(path!, fit: fit, fallback: fallback),
              ),
      ),
    );
  }
}

/// Photos whose thumb failed to load (uploaded before thumbs existed): straight to the full photo next time.
final _noThumb = <String>{};

class _NetworkPhoto extends ConsumerWidget {
  const _NetworkPhoto(this.path, {required this.fit, required this.fallback});

  final String path;
  final BoxFit fit;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saver = ref.watch(dataSaverProvider) == DataMode.saver;
    final thumb = _noThumb.contains(path) ? null : thumbPathFor(path);
    final still = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, box) {
      // Decode at display size, not the 1600px upload, to keep lists smooth on mid-range phones; saver caps it at 1.5x.
      final width = box.maxWidth.isFinite ? (box.maxWidth * (saver ? min(dpr, 1.5) : dpr)).round() : null;
      Widget image(String p, {Widget Function()? onError}) => CachedNetworkImage(
            imageUrl: publicImageUrl(p),
            fit: fit,
            fadeInDuration: still ? Duration.zero : Motion.normal,
            memCacheWidth: width,
            errorWidget: (_, _, _) => onError?.call() ?? fallback,
          );
      if (!saver || thumb == null) return image(path);
      return image(thumb, onError: () {
        _noThumb.add(path); // no thumb: the full photo now and from the next build on
        return image(path);
      });
    });
  }
}

/// "₹1,29,999  ₹1,39,999  7% off"
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.pricePaise, this.mrpPaise, this.large = false, this.prefix});

  final int pricePaise;
  final int? mrpPaise;
  final bool large;
  final String? prefix; // e.g. "From"

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    const tabular = [FontFeature.tabularFigures()];
    final off = mrpPaise == null ? 0 : discountPercent(pricePaise, mrpPaise!);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: Space.sm,
      children: [
        if (prefix != null) Text(prefix!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        Text(
          formatInr(pricePaise),
          style: (large ? t.headlineSmall : t.titleMedium)?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular),
        ),
        if (off > 0) ...[
          Text(
            formatInr(mrpPaise!),
            semanticsLabel: 'MRP ${formatInr(mrpPaise!)}',
            style: t.bodySmall?.copyWith(
              color: c.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              fontFeatures: tabular,
            ),
          ),
          Text('$off% off', style: t.labelMedium?.copyWith(color: c.secondary)),
        ],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Icon(icon, size: 36, color: c.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: Space.xl),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Space.sm),
              Text(message!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: PhosphorIconsRegular.cloudX,
        title: 'Couldn’t load this',
        message: friendlyError(error),
        action: isSessionError(error)
            ? FilledButton(
                // Dropping the dead local session lets the router send auth-only screens to /sign-in?from=<here>
                // (and back after sign-in); public screens just reload signed out.
                onPressed: () async {
                  final auth = ProviderScope.containerOf(context, listen: false).read(supabaseProvider).auth;
                  await auth.signOut(scope: SignOutScope.local).catchError((Object _) {});
                  onRetry?.call();
                },
                child: const Text('Sign in again'),
              )
            : onRetry == null
                ? null
                : OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                    label: const Text('Try again'),
                  ),
      );
}

/// Shown on tab roots (Cart, Repairs, Account) when signed out.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.icon, required this.title, required this.message, required this.from});

  final IconData icon;
  final String title;
  final String message;
  final String from;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: icon,
        title: title,
        message: message,
        action: FilledButton(
          onPressed: () => context.push('/sign-in?from=${Uri.encodeComponent(from)}'),
          child: const Text('Sign in'),
        ),
      );
}

/// Renders an AsyncValue with consistent loading / error / data handling.
/// [loading] should be a skeleton of the real layout (see `skeletonizer`).
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, required this.loading, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.normal,
        child: value.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (d) => KeyedSubtree(key: const ValueKey('data'), child: data(d)),
          loading: () => _DelayedReveal(key: const ValueKey('loading'), child: loading),
          error: (e, _) => KeyedSubtree(key: const ValueKey('error'), child: ErrorView(error: e, onRetry: onRetry)),
        ),
      );
}

/// Shows [child] only if loading lasts longer than a beat, so fast loads never flash a skeleton.
class _DelayedReveal extends StatefulWidget {
  const _DelayedReveal({super.key, required this.child});

  final Widget child;

  @override
  State<_DelayedReveal> createState() => _DelayedRevealState();
}

class _DelayedRevealState extends State<_DelayedReveal> {
  late final Timer _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 250), () => setState(() => _shown = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.normal,
        child: widget.child,
      );
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 5, this.onRemove});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final VoidCallback? onRemove; // set: at [min] the minus becomes a bin that removes the line

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: c.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value <= min && onRemove != null)
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(PhosphorIconsRegular.trash, size: 18),
            )
          else
            IconButton(
              tooltip: 'Decrease quantity',
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(PhosphorIconsRegular.minus, size: 18),
            ),
          Semantics(
            label: 'Quantity $value',
            excludeSemantics: true,
            child: SizedBox(
              width: 24,
              child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          IconButton(
            tooltip: 'Increase quantity',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(PhosphorIconsRegular.plus, size: 18),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.sm, Space.sm),
        child: Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge))),
            if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      );
}

/// Every yes/no confirmation in the app. The recommended choice is the filled button on the right. For
/// destructive actions that's the safe one ("Keep order"); the destructive one is quiet red text far left,
/// so a hurried thumb keeps things as they are. Returns true only when [action] was chosen.
Future<bool> confirmChoice(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  required String keep,
  bool destructive = false,
}) async {
  final c = Theme.of(context).colorScheme;
  const compact = Size(64, 44);
  final picked = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: destructive
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: c.error, minimumSize: compact),
                child: Text(action),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, false),
                style: FilledButton.styleFrom(minimumSize: compact),
                child: Text(keep),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(minimumSize: compact),
                child: Text(keep),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(minimumSize: compact),
                child: Text(action),
              ),
            ],
    ),
  );
  return picked ?? false;
}

/// Every url_launcher call goes through here. False when [uri] isn't allowed or nothing could open it.
Future<bool> launchExternal(Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
  if (!isAllowedExternalUri(uri)) return false;
  try {
    return await launchUrl(uri, mode: mode);
  } catch (_) {
    return false; // no app for it, or the platform refused
  }
}

void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    // an action keeps the bar up only for screen-reader users (they need time to reach it); others see it time out
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      persist: action != null && MediaQuery.accessibleNavigationOf(context),
    ));
}

/// The Shyam Mobiles mark (logo 6 in docs/logo-ideas.html): Krishna's peacock feather drawn as a grid of
/// dots, like a phone screen up close, with the eye left open around a grey core.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34, this.onDark = false});

  final double size;
  final bool onDark; // translucent tile for use on the black hero

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Shyam Mobiles',
        child: CustomPaint(size: Size.square(size), painter: _BrandMarkPainter(onDark)),
      );
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.onDark);

  final bool onDark;

  // Same geometry as the logo page and the launcher icon (100-unit box).
  static final List<(Offset, _Dot)> _dots = () {
    final feather = Path()
      ..moveTo(50, 14)
      ..cubicTo(69, 29, 76, 50, 71, 67)
      ..cubicTo(66, 84, 34, 84, 29, 67)
      ..cubicTo(24, 50, 31, 29, 50, 14)
      ..close();
    bool inOval(Offset p, double cx, double cy, double rx, double ry) =>
        ((p.dx - cx) / rx) * ((p.dx - cx) / rx) + ((p.dy - cy) / ry) * ((p.dy - cy) / ry) <= 1;
    final dots = <(Offset, _Dot)>[];
    for (var y = 17.0; y <= 82; y += 5.4) {
      for (var x = 25.0; x <= 75; x += 5.4) {
        final p = Offset(x, y);
        if (!feather.contains(p)) continue;
        if (inOval(p, 50, 63, 7, 8.5)) {
          dots.add((p, _Dot.core));
        } else if (!inOval(p, 50, 61, 14.5, 17.5)) {
          dots.add((p, inOval(p, 50, 61, 20, 23) ? _Dot.ring : _Dot.plain));
        }
      }
    }
    return dots;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(26)),
      Paint()..color = onDark ? Colors.white.withValues(alpha: 0.14) : BrandColors.ink,
    );
    final white = Paint()..color = Colors.white;
    final paints = {_Dot.plain: white, _Dot.ring: Paint()..color = BrandColors.gold, _Dot.core: Paint()..color = BrandColors.sky};
    for (final (p, dot) in _dots) {
      canvas.drawCircle(p, 2.1, paints[dot]!);
    }
    canvas.drawLine(
      const Offset(50, 84),
      const Offset(50, 92),
      white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.onDark != onDark;
}

/// White feather dots, a gold ring around the open eye, and a sky-blue core: a peacock feather.
enum _Dot { plain, ring, core }

/// Fades and rises into place on first build, [index] beats after the first (a stagger). Skipped when the phone asks
/// for less motion. The stagger is the effect's own delay: Animate's `delay` is a Timer, which a quick unmount trips.
extension EnterMotion on Widget {
  Widget enter(BuildContext context, {int index = 0}) {
    if (MediaQuery.disableAnimationsOf(context)) return this;
    final delay = Duration(milliseconds: 55 * index.clamp(0, 8));
    return animate()
        .fadeIn(delay: delay, duration: Motion.enter, curve: Curves.easeOutCubic)
        .slideY(begin: 0.12, end: 0, delay: delay, duration: Motion.enter, curve: Curves.easeOutCubic);
  }
}

/// Pops [child] when [trigger] changes (cart count, wishlist heart), not on first build.
class Bump extends StatefulWidget {
  const Bump({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<Bump> createState() => _BumpState();
}

class _BumpState extends State<Bump> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);
  late final _scale = _c.drive(Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)));

  @override
  void didUpdateWidget(Bump old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}

/// WhatsApp's own glyph in its brand green. Third-party marks keep their native colours, never the app's ink.
class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({super.key, this.size});

  final double? size;

  static const green = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) => Icon(PhosphorIconsFill.whatsappLogo, size: size, color: green);
}

enum TagTone { info, ok, deal, bad }

/// Small status pill ("In stock", "Only 2 left", "Shipped"). Same look as `.tag` in docs/mockup.html.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = TagTone.info, this.icon});

  final String text;
  final TagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      TagTone.info => (BrandColors.peacockMist, BrandColors.peacockInk),
      TagTone.ok => (c.secondaryContainer, c.onSecondaryContainer),
      TagTone.deal => (c.tertiaryContainer, c.onTertiaryContainer),
      TagTone.bad => (c.errorContainer, c.onErrorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: Space.xs)],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
