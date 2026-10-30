import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/physics.dart';
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

/// Rises in the first time it scrolls into view, once. Already on screen at first: just shown.
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
    return box == null || !box.attached || box.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height - 24;
  }

  void _check() {
    if (!mounted || !_inView()) return;
    _position?.removeListener(_check);
    _position = null;
    _c.forward();
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
    _c.animateTo(0.96, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
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
