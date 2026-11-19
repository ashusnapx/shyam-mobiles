import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/physics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../network.dart';
import '../theme/tokens.dart';

// The app's motion beyond `.enter` and Bump: scroll-linked drift (Lenis's idea), springs and counters (anime.js's).
// Everything here is transform, opacity or a number; all of it is off when the phone asks for less motion.

/// Parallax and the logo ripple are skipped on low-RAM phones; counters and presses stay.
final richMotionProvider = Provider<bool>((ref) => !ref.watch(networkProvider.select((s) => s.lowRam)));

const _tabular = [FontFeature.tabularFigures()];

/// [child] drifts down by [rate] of how far its page has scrolled, so it moves slower than the page, and fades
/// towards [fadeTo] over [distance]. Clip the parent to keep it in its frame. The child never rebuilds.
class Parallax extends ConsumerWidget {
  const Parallax({super.key, required this.child, this.rate = 0.3, this.fadeTo = 1, this.distance = 400});

  final Widget child;
  final double rate;
  final double fadeTo;
  final double distance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || MediaQuery.disableAnimationsOf(context) || !ref.watch(richMotionProvider)) return child;
    return AnimatedBuilder(
      animation: position,
      child: child,
      builder: (context, child) {
        final d = position.hasPixels ? position.pixels.clamp(0.0, distance) : 0.0;
        final moved = Transform.translate(offset: Offset(0, d * rate), child: child);
        return fadeTo == 1 || d == 0 ? moved : Opacity(opacity: 1 - (1 - fadeTo) * d / distance, child: moved);
      },
    );
  }
}

/// Tracks how far the scroll view inside is pulled past its top (pull to refresh, Android's stretch) for [PullScale].
class OverscrollScope extends StatefulWidget {
  const OverscrollScope({super.key, required this.child});

  final Widget child;

  @override
  State<OverscrollScope> createState() => _OverscrollScopeState();
}

class _OverscrollScopeState extends State<OverscrollScope> {
  final _pull = ValueNotifier<double>(0);

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _pull.value = (_pull.value - n.overscroll).clamp(0, 160);
    } else if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      _pull.value = 0;
    }
    return false; // the refresh indicator above still gets it
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: _onScroll,
    child: _Pull(notifier: _pull, child: widget.child),
  );
}

class _Pull extends InheritedWidget {
  const _Pull({required this.notifier, required super.child});

  final ValueNotifier<double> notifier;

  @override
  bool updateShouldNotify(_Pull old) => old.notifier != notifier;
}

/// Grows a touch (up to 5%) while the page is pulled down past its top, and springs back on release.
class PullScale extends ConsumerWidget {
  const PullScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pull = context.getInheritedWidgetOfExactType<_Pull>()?.notifier;
    if (pull == null || MediaQuery.disableAnimationsOf(context) || !ref.watch(richMotionProvider)) return child;
    return ValueListenableBuilder<double>(
      valueListenable: pull,
      child: child,
      builder: (context, p, child) => AnimatedScale(
        scale: 1 + p / 3200,
        duration: p == 0 ? Motion.normal : Duration.zero, // follows the finger, settles on release
        curve: Curves.easeOutBack,
        child: child,
      ),
    );
  }
}

/// Rises in the first time it scrolls into view, once. Already on screen at first: just shown. For a child of a
/// SliverToBoxAdapter (built up front, laid out as it nears the screen); a lazily built list item just shows.
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({super.key, required this.child});

  final Widget child;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

final _rise = Tween(begin: const Offset(0, 0.3), end: Offset.zero);

class _RevealOnScrollState extends State<RevealOnScroll> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.enter, value: 1);
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  ScrollPosition? _position;
  bool _started = false;
  bool _queued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || MediaQuery.disableAnimationsOf(context)) return;
    _started = true;
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inView()) return;
      _c.value = 0; // below the fold: wait for it
      _position = position..addListener(_check);
    });
  }

  bool _inView() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return true;
    if (!box.hasSize) return false; // a sliver past the cache extent isn't laid out yet: well below the fold
    return box.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height - 24;
  }

  /// Measured after the frame the scroll lays out, not mid-scroll (it may not be laid out yet).
  void _check() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || _position == null || !_inView()) return;
      _position!.removeListener(_check);
      _position = null;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _curve.drive(_rise), child: widget.child),
    );
  }
}

/// Cards and tiles dip a little under the finger and spring back on release. It only listens: the child keeps its
/// own tap (an InkWell), ripple and semantics. A finger that starts scrolling lets go of it.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});

  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(mass: 1, stiffness: 520, damping: 16); // a slight overshoot
  late final _c = AnimationController.unbounded(vsync: this, value: 1);
  Offset? _down;

  void _press(PointerDownEvent e) {
    _down = e.position;
    _c.animateTo(0.96, duration: Motion.press, curve: Curves.easeOut);
  }

  void _release() {
    if (_down == null) return;
    _down = null;
    _c.animateWith(SpringSimulation(_spring, _c.value, 1, 0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return Listener(
      onPointerDown: _press,
      onPointerMove: (e) {
        if (_down != null && (e.position - _down!).distance > kTouchSlop) _release();
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: ScaleTransition(scale: _c, child: widget.child),
    );
  }
}

/// A number that rolls to each new value, in tabular figures so the digits don't jiggle. [fromZero] counts up from 0
/// the first time it shows (stats, a new saving); otherwise it starts on the value and only moves when it changes.
class CountTo extends StatelessWidget {
  const CountTo(
    this.value, {
    super.key,
    this.format = formatInr,
    this.style,
    this.fromZero = false,
    this.semanticsLabel,
  });

  final int value; // paise for the default [format]
  final String Function(int) format;
  final TextStyle? style;
  final bool fromZero;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final style = (this.style ?? const TextStyle()).copyWith(fontFeatures: _tabular);
    final label = semanticsLabel ?? format(value); // screen readers get the final value, not every step
    if (MediaQuery.disableAnimationsOf(context)) return Text(format(value), semanticsLabel: label, style: style);
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: fromZero ? 0 : value, end: value),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), semanticsLabel: label, style: style),
    );
  }
}

/// White at this strength sweeps over the hero's glass panel: white text there stays 4.5:1 (generative_test).
const sweepAlpha = 0.10;

/// The Home hero's slide motion. Each effect starts when its slide shows (a new slide is a new widget); TickerMode
/// freezes it off screen, behind another tab and in the carousel's invisible sizing copies; a paused app draws no
/// frames. All of it is off when the phone asks for less motion.
extension HeroMotion on Widget {
  /// Slow zoom and drift on a photo (Ken Burns). Clip the parent.
  Widget kenBurns(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? this
      : animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1, end: 1.12, duration: 9.seconds, curve: Curves.easeInOut)
          .move(begin: const Offset(-3, 2), end: const Offset(3, -2), duration: 9.seconds, curve: Curves.easeInOut);

  /// A soft band of light crosses this every few seconds; [radius] rounds it to the panel.
  Widget sweep(BuildContext context, {double radius = Radii.lg}) => MediaQuery.disableAnimationsOf(context)
      ? this
      : animate(onPlay: (c) => c.repeat()).custom(
          delay: 3.seconds,
          duration: 1200.ms,
          curve: Curves.easeInOut,
          builder: (_, v, child) => Stack(
            children: [
              child,
              if (v > 0 && v < 1)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: FractionalTranslation(translation: Offset(v * 2.4 - 1.2, 0), child: const DecoratedBox(decoration: _sheen)),
                    ),
                  ),
                ),
            ],
          ),
        );

  /// Grows in from small, a beat after its slide arrives (the price, the countdown).
  Widget popIn(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? this
      : animate()
          .fadeIn(delay: 250.ms, duration: 250.ms)
          .scaleXY(begin: 0.7, end: 1, delay: 250.ms, duration: 450.ms, curve: Curves.easeOutBack, alignment: Alignment.centerLeft);
}

const _sheen = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment(-1, -0.5),
    end: Alignment(1, 0.5),
    stops: [0.3, 0.5, 0.7],
    colors: [Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, sweepAlpha), Color(0x00FFFFFF)],
  ),
);
