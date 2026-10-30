import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';

/// The sign-in and code screens' hero: the home card's deep peacock, drifting once through the three hero tones and
/// back (12 s, then it rests: no endless repaint on a cheap phone; still with reduced motion and on low-RAM phones),
/// feather rings, and the colour mark, whose dots ripple out once. [compact] folds it to a bar while typing; white
/// text passes AA on every tone.
class AuthHero extends ConsumerStatefulWidget {
  const AuthHero({super.key, required this.compact, required this.leading, this.overlap = 26});

  final bool compact;
  final Widget leading; // Close on sign-in, Back on the code screen
  final double overlap; // the white sheet below rides up over the hero by this much

  @override
  ConsumerState<AuthHero> createState() => _AuthHeroState();
}

class _AuthHeroState extends ConsumerState<AuthHero> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context) && ref.read(richMotionProvider)) _drift.forward();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const onHero = Colors.white;
    final still = MediaQuery.disableAnimationsOf(context);
    final leading = Transform.translate(offset: const Offset(-Space.md, 0), child: widget.leading);
    final full = Column(
      key: const ValueKey('full'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(height: Space.lg),
        const BrandMark(size: 52, onDark: true, ripple: true),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text('Welcome to\nShyam Mobiles', style: t.displayLarge?.copyWith(color: onHero)),
        ),
        const SizedBox(height: 10),
        Text(
          'Sign in or create your account with a one-time code. No password to remember.',
          style: t.bodyMedium?.copyWith(color: onHero.withValues(alpha: 0.85)),
        ),
      ],
    );
    final bar = Row(
      key: const ValueKey('compact'),
      children: [
        leading,
        const BrandMark(size: 28, onDark: true),
        const SizedBox(width: Space.md),
        Flexible(
          child: Semantics(
            header: true,
            child: Text('Shyam Mobiles', style: t.displaySmall?.copyWith(fontSize: 22, color: onHero)),
          ),
        ),
      ],
    );
    final duration = still ? Duration.zero : Motion.normal;
    // never taller than the space above the keyboard: while it slides up, the folding hero clips instead of
    // pushing the form off the screen
    final room = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: room),
      child: CustomPaint(
        painter: _DriftPainter(_drift),
        // the drift repaints only the gradient: the rings and text sit on their own layer
        child: RepaintBoundary(
          child: CustomPaint(
            painter: const _RipplePainter(),
            child: AnimatedPadding(
              duration: duration,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                Space.xl,
                MediaQuery.paddingOf(context).top + Space.xs,
                Space.xl,
                (widget.compact ? Space.md : Space.xxl) + widget.overlap,
              ),
              child: AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: still ? Duration.zero : Motion.fast,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                  child: widget.compact ? bar : full,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The diagonal hero gradient, easing from one of [heroGradients] to the next (peacock, marigold, emerald).
class _DriftPainter extends CustomPainter {
  _DriftPainter(this.drift) : super(repaint: drift);

  final Animation<double> drift;

  @override
  void paint(Canvas canvas, Size size) {
    final at = drift.value * heroGradients.length;
    final from = heroGradients[at.floor() % heroGradients.length];
    final to = heroGradients[(at.floor() + 1) % heroGradients.length];
    final f = Curves.easeInOut.transform(at - at.floor()); // lingers on each tone
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [for (var i = 0; i < from.length; i++) Color.lerp(from[i], to[i], f)!],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_DriftPainter old) => old.drift != drift;
}

/// A soft glow and feather-eye rings rising from below the hero.
class _RipplePainter extends CustomPainter {
  const _RipplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 1.2);
    final glow = Rect.fromCircle(center: centre, radius: size.height * 0.75);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [BrandColors.gold.withValues(alpha: 0.22), BrandColors.gold.withValues(alpha: 0)],
        ).createShader(glow),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.08);
    for (var r = 20.0; r < size.height * 1.3; r += 20) {
      canvas.drawOval(Rect.fromCenter(center: centre, width: r * 2.6, height: r * 2), ring);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => false;
}

/// The hero's round translucent button (Close, Back).
Widget heroButton({required String tooltip, required IconData icon, required VoidCallback onPressed}) => IconButton(
  tooltip: tooltip,
  onPressed: onPressed,
  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.14), foregroundColor: Colors.white),
  icon: Icon(icon, size: 20),
);
