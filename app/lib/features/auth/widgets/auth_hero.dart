import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/generative.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';

/// The sign-in and code screens' hero: the shop's own deep colours (the 'shyam-mobiles' [deepPalette], so it's the same
/// on every phone) with soft light drifting through it for one slow cycle (18 s, then it rests: no endless repaint on
/// a cheap phone; still with reduced motion and on low-RAM phones), and the colour mark, whose dots ripple out once.
/// [compact] folds it to a bar while typing; white text passes 4.5:1 on every stop.
class AuthHero extends ConsumerStatefulWidget {
  const AuthHero({super.key, required this.compact, required this.leading, this.overlap = 26});

  final bool compact;
  final Widget leading; // Close on sign-in, Back on the code screen
  final double overlap; // the white sheet below rides up over the hero by this much

  @override
  ConsumerState<AuthHero> createState() => _AuthHeroState();
}

const _seed = 'shyam-mobiles';
final _palette = deepPalette(_seed);

class _AuthHeroState extends ConsumerState<AuthHero> {
  bool _drifting = false;
  Timer? _rest;

  @override
  void initState() {
    super.initState();
    if (!ref.read(richMotionProvider)) return;
    _drifting = true;
    _rest = Timer(const Duration(seconds: 18), () {
      if (mounted) setState(() => _drifting = false); // one cycle of the aurora's drift, then still
    });
  }

  @override
  void dispose() {
    _rest?.cancel();
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
    return AuroraBackground(
      palette: _palette,
      seed: _seed,
      still: !_drifting,
      child: RepaintBoundary(
        // the drift repaints the light, not the text
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
    );
  }
}

/// The hero's round translucent button (Close, Back).
Widget heroButton({required String tooltip, required IconData icon, required VoidCallback onPressed}) => IconButton(
  tooltip: tooltip,
  onPressed: onPressed,
  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.14), foregroundColor: Colors.white),
  icon: Icon(icon, size: 20),
);
