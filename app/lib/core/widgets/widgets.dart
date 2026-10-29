import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../errors.dart';
import '../format.dart';
import '../supabase.dart';
import '../theme/tokens.dart';

/// Product photo from the `product-images` bucket on a soft tinted well, with an icon when there's no photo.
class ProductImage extends StatelessWidget {
  const ProductImage(this.path, {super.key, this.aspectRatio = 1, this.radius = Radii.lg, this.padding = Space.md});

  final String? path;
  final double aspectRatio;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fallback = Center(
      child: Icon(PhosphorIconsLight.deviceMobile, size: 40, color: c.onSurfaceVariant.withValues(alpha: 0.5)),
    );
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(radius)),
        child: path == null
            ? fallback
            : Padding(
                padding: EdgeInsets.all(padding),
                // Decode at display size, not the 1600px upload, to keep lists smooth on mid-range phones.
                child: LayoutBuilder(
                  builder: (context, box) => CachedNetworkImage(
                    imageUrl: publicImageUrl(path!),
                    fit: BoxFit.contain,
                    fadeInDuration: Motion.normal,
                    memCacheWidth: box.maxWidth.isFinite
                        ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round()
                        : null,
                    errorWidget: (_, _, _) => fallback,
                  ),
                ),
              ),
      ),
    );
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
        action: onRetry == null
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
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 5});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

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

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Peacock-feather eye in greyscale on an ink tile: the Shyam Mobiles mark. Same geometry as docs/mockup.html.
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

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 32;
    Rect oval(double cx, double cy, double rx, double ry) =>
        Rect.fromCenter(center: Offset(cx * u, cy * u), width: rx * 2 * u, height: ry * 2 * u);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(9 * u)),
      Paint()..color = onDark ? Colors.white.withValues(alpha: 0.14) : BrandColors.ink,
    );
    canvas.drawOval(oval(16, 17.5, 8.5, 10.5), Paint()..color = Colors.white);
    canvas.drawOval(oval(16, 18.5, 5.5, 7), Paint()..color = BrandColors.mist);
    canvas.drawOval(oval(16, 19, 3, 3.9), Paint()..color = BrandColors.ink);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.onDark != onDark;
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
      TagTone.info => (c.primaryContainer, c.onPrimaryContainer),
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
