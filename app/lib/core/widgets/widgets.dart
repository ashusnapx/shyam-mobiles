import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
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
import 'blocks.dart' show toneColors;
import 'motion.dart';

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

/// "₹1,29,999  ₹1,39,999  7% off". [stacked] is the product tile's: the price on one line and the MRP with "% off"
/// on a fixed-height line under it (empty with no discount), so every tile in a row is the same height.
/// [showSaving] (the product page) adds "You save ₹3,000 (4%)" under the price.
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.pricePaise,
    this.mrpPaise,
    this.large = false,
    this.prefix,
    this.stacked = false,
    this.showSaving = false,
  });

  final int pricePaise;
  final int? mrpPaise;
  final bool large;
  final String? prefix; // e.g. "From"
  final bool stacked;
  final bool showSaving;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    const tabular = [FontFeature.tabularFigures()];
    final off = mrpPaise == null ? 0 : discountPercent(pricePaise, mrpPaise!);
    final mrp = off > 0
        ? Text(
            formatInr(mrpPaise!),
            semanticsLabel: 'MRP ${formatInr(mrpPaise!)}',
            style: t.bodySmall?.copyWith(
              color: c.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              fontFeatures: tabular,
            ),
          )
        : null;
    final offStyle = t.labelMedium?.copyWith(color: BrandColors.emerald, fontWeight: FontWeight.w700);
    if (stacked) {
      final price = Text(
        [?prefix, formatInr(pricePaise)].join(' '),
        maxLines: 1,
        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // a long price shrinks to fit instead of wrapping
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: price),
          const SizedBox(height: 2),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(13) * 1.3,
            child: mrp == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(children: [mrp, const SizedBox(width: 6), Text('$off% off', style: offStyle)]),
                  ),
          ),
        ],
      );
    }
    final tag = Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: Space.sm,
      children: [
        if (prefix != null) Text(prefix!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        if (large) // the product page: rolls to the new price when the variant changes
          CountTo(pricePaise, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800))
        else
          Text(formatInr(pricePaise), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
        if (mrp != null) ...[mrp, if (!showSaving) Text('$off% off', style: offStyle)],
      ],
    );
    if (!showSaving || mrp == null) return tag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        tag,
        const SizedBox(height: 2),
        Text(
          'You save ${formatInr(mrpPaise! - pricePaise)} ($off%)',
          style: t.labelLarge?.copyWith(color: BrandColors.emerald, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The icon on two soft circles in the screen's [Worlds] colour, a title in the brand face and one way forward; sits
/// a little above centre.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.art,
    this.tone = Worlds.shop,
  });

  final IconData icon;
  final Widget? art; // an illustration in place of the icon's circle
  final String title;
  final String? message;
  final Widget? action;
  final Tint tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final (bg, fg) = tone;
    return Align(
      alignment: const Alignment(0, -0.2),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            art ??
                ExcludeSemantics(
                  child: Container(
                    width: 152,
                    height: 152,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: bg.withValues(alpha: 0.45), shape: BoxShape.circle),
                    child: Container(
                      width: 112,
                      height: 112,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                      child: Icon(icon, size: IconSizes.xl, color: fg),
                    ),
                  ),
                ),
            const SizedBox(height: Space.xl),
            Text(
              title,
              style: t.displaySmall?.copyWith(fontSize: 22, height: 1.2, letterSpacing: -0.4),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: Space.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(message!, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant), textAlign: TextAlign.center),
              ),
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
        // grey, not red: no signal is not something the customer did wrong
        tone: (Theme.of(context).colorScheme.surfaceContainerHigh, BrandColors.graphite),
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
  const SignInPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.from,
    this.tone = Worlds.shop,
  });

  final IconData icon;
  final String title;
  final String message;
  final String from;
  final Tint tone; // the tab's [Worlds] colour

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: icon,
        tone: tone,
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
    _timer = Timer(Motion.normal, () => setState(() => _shown = true));
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

/// Every section title in the app: the brand face (titleLarge), an [accent] bar before it when it sits on a coloured
/// panel, and a 48 dp "See all ›" ([onSeeAll]) that opens the full list of what the section shows. 32 dp above it
/// (one section from the next), 12 dp to its content. [inset] false: the list around it already has side padding;
/// [gutter] is the side padding otherwise. [actionLabel] / [onAction] are the older spelling of a link.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.accent,
    this.onSeeAll,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.inset = true,
    this.gutter = Space.lg,
    this.top,
  });

  final String title;
  final Color? accent;
  final VoidCallback? onSeeAll;
  final String? actionLabel; // default "See all"
  final VoidCallback? onAction;
  final Widget? trailing; // in place of the link
  final bool inset;
  final double gutter;
  final double? top; // default [Space.section]

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final onLink = onSeeAll ?? onAction;
    final side = inset ? gutter : 0.0;
    // the link's own padding lines its caret up with the gutter
    final end = inset ? max(0.0, gutter - Space.md) : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, top ?? Space.section, end, Space.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            if (accent != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
                child: const SizedBox(width: 4, height: 16),
              ),
              const SizedBox(width: Space.sm),
            ],
            Expanded(child: Semantics(header: true, child: Text(title, style: t.titleLarge))),
            if (trailing != null)
              trailing!
            else if (onLink != null || actionLabel != null)
              TextButton.icon(
                onPressed: onLink,
                iconAlignment: IconAlignment.end,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                ),
                icon: const Icon(PhosphorIconsBold.caretRight, size: 14),
                label: Text(actionLabel ?? 'See all'),
              ),
          ],
        ),
      ),
    );
  }
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

void showMessage(BuildContext context, String message, {SnackBarAction? action}) =>
    showMessageOn(ScaffoldMessenger.of(context), message, action: action);

/// [showMessage] for a messenger read before an await, when the screen's context may be gone by then.
void showMessageOn(ScaffoldMessengerState messenger, String message, {SnackBarAction? action}) {
  messenger
    ..hideCurrentSnackBar()
    // an action keeps the bar up only for screen-reader users (they need time to reach it); others see it time out
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      persist: action != null && MediaQuery.accessibleNavigationOf(messenger.context),
    ));
}

/// The Shyam Mobiles mark (logo 6 in docs/logo-ideas.html): Krishna's peacock feather drawn as a grid of
/// dots, like a phone screen up close, with the eye left open around a grey core.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34, this.onDark = false, this.ripple = false});

  final double size;
  final bool onDark; // translucent tile for use on the black hero
  final bool ripple; // the dots pop in once, rippling out from the eye (sign-in, order placed)

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Shyam Mobiles',
        child: ripple
            ? _RippleMark(size: size, onDark: onDark)
            : CustomPaint(size: Size.square(size), painter: _BrandMarkPainter(onDark)),
      );
}

/// anime.js's grid stagger from the centre: each dot pops in ~700 ms, the nearer the eye the sooner. Once per
/// mount; skipped (the plain mark) with reduced motion and on low-RAM phones.
class _RippleMark extends ConsumerStatefulWidget {
  const _RippleMark({required this.size, required this.onDark});

  final double size;
  final bool onDark;

  @override
  ConsumerState<_RippleMark> createState() => _RippleMarkState();
}

class _RippleMarkState extends ConsumerState<_RippleMark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.slow, value: 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context) && ref.read(richMotionProvider)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(widget.size), painter: _BrandMarkPainter(widget.onDark, _c));
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.onDark, [this.ripple]) : super(repaint: ripple);

  final bool onDark;
  final Animation<double>? ripple; // 0 → 1; null: all dots shown

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
      Paint()..color = onDark ? Colors.white.withValues(alpha: 0.14) : BrandColors.logoInk,
    );
    final white = Paint()..color = Colors.white;
    final paints = {_Dot.plain: white, _Dot.ring: Paint()..color = BrandColors.logoGold, _Dot.core: Paint()..color = BrandColors.sky};
    final t = ripple?.value ?? 1;
    for (final (p, dot) in _dots) {
      // the eye (50, 63) first, the feather's tip and edges last (≈ 46 units away)
      final local = t >= 1 ? 1.0 : ((t - 0.5 * (p - const Offset(50, 63)).distance / 46) / 0.5).clamp(0.0, 1.0);
      if (local > 0) canvas.drawCircle(p, 2.1 * Curves.easeOutBack.transform(local), paints[dot]!);
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
  bool shouldRepaint(_BrandMarkPainter old) => old.onDark != onDark || old.ripple != ripple;
}

/// White feather dots, a gold ring around the open eye, and a sky-blue core: a peacock feather.
enum _Dot { plain, ring, core }

/// Fades and rises into place on first build, [index] beats after the first (a stagger). Skipped when the phone asks
/// for less motion. The stagger is the effect's own delay: Animate's `delay` is a Timer, which a quick unmount trips.
extension EnterMotion on Widget {
  Widget enter(BuildContext context, {int index = 0}) {
    if (MediaQuery.disableAnimationsOf(context)) return this;
    final delay = Motion.stagger * index.clamp(0, 8);
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
  late final _c = AnimationController(vsync: this, duration: Motion.bump, value: 1);
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

  static const green = BrandColors.whatsapp;

  @override
  Widget build(BuildContext context) => Icon(PhosphorIconsFill.whatsappLogo, size: size, color: green);
}

/// What a status means, and so its colour ([toneColors]): info / in progress (peacock), ok / done or saved (emerald),
/// deal / act soon (gold), repair (saffron), neutral / closed but nothing went wrong (grey), bad / an error (red).
enum TagTone { info, ok, deal, repair, neutral, bad }

/// Small status pill ("In stock", "Only 2 left", "Shipped"). Same look as `.tag` in docs/mockup.html.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = TagTone.info, this.icon});

  final String text;
  final TagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(tone);
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.xs)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: IconSizes.xs, color: fg), const SizedBox(width: Space.xs)],
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

/// A list row's or a quick action's icon on a rounded square of its [tint] (36 dp, a 20 dp icon by default).
class IconWell extends StatelessWidget {
  const IconWell(this.icon, {super.key, required this.tint, this.size = 36, this.radius = Radii.chip, this.iconSize = IconSizes.md});

  final IconData icon;
  final Tint tint;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(radius)),
        child: SizedBox.square(dimension: size, child: Icon(icon, size: iconSize, color: tint.$2)),
      );
}

/// The one spinner inside a busy button, in the button's own text colour.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: IconTheme.of(context).color),
      );
}

/// Which glass: [bar] for pinned bars (blur 24), [card] for chips over a light aurora or photo (blur 16), [onDeep] for
/// pills on a hero gradient (a tint, no blur: a smooth gradient looks the same blurred).
enum GlassKind { bar, card, onDeep }

/// Frosted glass ([Glass]) that blurs what scrolls under it, with a hairline edge. At most two on screen (a bar and
/// the nav); low-RAM phones and reduced motion get the opaque fallback.
class GlassSurface extends ConsumerWidget {
  const GlassSurface({super.key, required this.child, this.kind = GlassKind.bar, this.radius = 0, this.border});

  final Widget child;
  final GlassKind kind;
  final double radius;
  final BoxBorder? border; // default: a hairline all round when rounded, none when square (the caller picks the edge)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rich = ref.watch(richMotionProvider) && !MediaQuery.disableAnimationsOf(context);
    final shape = BorderRadius.circular(radius);
    final deep = kind == GlassKind.onDeep;
    final blur = rich && !deep;
    final color = switch (kind) {
      GlassKind.onDeep => Glass.onDeep,
      _ when !rich => Glass.fallback,
      GlassKind.bar => Glass.bar,
      GlassKind.card => Glass.card,
    };
    final veil = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius > 0 ? shape : null,
        border: border ?? (radius > 0 ? Border.all(color: deep ? Glass.hairlineOnDeep : Glass.hairline) : null),
      ),
      child: child,
    );
    if (!blur) return veil;
    final sigma = kind == GlassKind.bar ? Glass.barBlur : Glass.cardBlur;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: veil),
    );
  }
}
