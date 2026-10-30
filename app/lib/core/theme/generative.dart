import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Colours made by maths instead of a fixed list: a seed (a product id, a banner id, a category slug) picks a hue and
/// a harmony, and the colours are built in OKLCH so equal steps look equal and every result has the same calm
/// lightness. The same seed always gives the same colours, so an item keeps its look everywhere.
/// Deep palettes carry white text (each stop is darkened until it passes 4.5:1 against white); soft palettes are
/// near-white bands with an accent that passes 3:1 on them.
class GenPalette {
  const GenPalette({required this.stops, required this.glows, required this.accent, required this.band});

  final List<Color> stops; // gradient, 3 stops
  final List<Color> glows; // the light blobs over it
  final Color accent; // pills, icons, dots
  final Color band; // the soft background a section or tile sits on
}

/// 32-bit FNV-1a: a small, stable hash so a seed picks the same hue on every device and every run.
int seedHash(String seed) {
  var h = 0x811C9DC5;
  for (final unit in seed.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Hue offsets that look good together: mostly analogous, one with a quiet complementary hint. No triads: red and
/// green side by side look cheap.
const _harmonies = [
  [0.0, 28.0, 56.0],
  [0.0, -32.0, 32.0],
  [0.0, 35.0, 70.0],
  [0.0, -25.0, 165.0],
];

GenPalette deepPalette(String seed) {
  final h = seedHash(seed);
  var hue = (h % 360).toDouble();
  // deep yellows and olive greens come out brown; nudge the base hue past that band
  if (hue > 70 && hue < 115) hue += 45;
  final offsets = _harmonies[(h >> 9) % _harmonies.length];
  final chroma = 0.10 + ((h >> 13) % 5) * 0.01; // 0.10..0.14
  final stops = [
    for (final (i, o) in offsets.indexed) _readableOnWhite(oklch(0.30 + i * 0.05, chroma, hue + o)),
  ];
  return GenPalette(
    stops: stops,
    glows: [for (final o in offsets) oklch(0.78, 0.13, hue + o + 12)],
    accent: oklch(0.82, 0.14, hue + offsets[1]),
    band: oklch(0.965, 0.02, hue),
  );
}

GenPalette softPalette(String seed) {
  final h = seedHash(seed);
  final hue = (h % 360).toDouble();
  final offsets = _harmonies[(h >> 9) % _harmonies.length];
  final band = oklch(0.96, 0.04, hue);
  var accent = oklch(0.52, 0.15, hue);
  for (var l = 0.52; contrast(accent, band) < 3 && l > 0.2; l -= 0.03) {
    accent = oklch(l, 0.15, hue);
  }
  return GenPalette(
    stops: [band, oklch(0.965, 0.035, hue + offsets[1]), oklch(0.975, 0.03, hue + offsets[2])],
    glows: [for (final o in offsets) oklch(0.88, 0.09, hue + o).withValues(alpha: 0.7)],
    accent: accent,
    band: band,
  );
}

/// OKLCH → sRGB (Björn Ottosson's OKLab matrices). Out-of-gamut colours lose chroma until they fit.
Color oklch(double l, double c, double hueDeg) {
  var chroma = c;
  while (true) {
    final hr = hueDeg * math.pi / 180;
    final a = chroma * math.cos(hr), b = chroma * math.sin(hr);
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    final ll = l_ * l_ * l_, mm = m_ * m_ * m_, ss = s_ * s_ * s_;
    final r = 4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss;
    final g = -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss;
    final bl = -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss;
    const eps = 1e-6;
    final inGamut = [r, g, bl].every((x) => x >= -eps && x <= 1 + eps);
    if (inGamut || chroma <= 0) {
      int channel(double x) {
        final v = x.clamp(0.0, 1.0);
        final srgb = v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
        return (srgb * 255).round().clamp(0, 255);
      }

      return Color.fromARGB(255, channel(r), channel(g), channel(bl));
    }
    chroma = math.max(0, chroma - 0.005);
  }
}

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _readableOnWhite(Color c) {
  var out = c;
  // darken in small steps until white text passes AA (4.5:1)
  for (var i = 0; contrast(out, Colors.white) < 4.5 && i < 20; i++) {
    out = Color.lerp(out, Colors.black, 0.06)!;
  }
  return out;
}

/// A gradient with large soft light blobs over it (an aurora): looks blurred, but it's radial gradients only, so it's
/// cheap on a ₹10k phone. [drift] slowly moves the blobs; it's off when the phone asks for less motion, and [still]
/// (low-RAM phones, skeletons, previews) paints one frame and never animates.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({
    super.key,
    required this.palette,
    this.seed = '',
    this.drift = true,
    this.still = false,
    this.child,
  });

  final GenPalette palette;
  final String seed; // places the blobs; usually the same seed as the palette
  final bool drift;
  final bool still;
  final Widget? child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 18));

  bool get _animate => widget.drift && !widget.still && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AuroraBackground old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_animate && TickerMode.valuesOf(context).enabled) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _AuroraPainter(widget.palette, seedHash(widget.seed), _c),
          child: widget.child ?? const SizedBox.expand(), // a CustomPaint with no child would size itself to zero
        ),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.p, this.hash, this.t) : super(repaint: t);

  final GenPalette p;
  final int hash;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final angle = (hash % 360) * math.pi / 180;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(math.cos(angle), math.sin(angle)),
          end: Alignment(-math.cos(angle), -math.sin(angle)),
          colors: p.stops,
        ).createShader(rect),
    );
    final side = math.max(size.width, size.height);
    for (var i = 0; i < p.glows.length; i++) {
      final bits = hash >> (i * 7);
      final phase = (bits % 628) / 100 + t.value * 2 * math.pi;
      final center = Offset(
        size.width * (0.15 + (bits % 70) / 100) + math.cos(phase) * side * 0.04,
        size.height * (0.10 + ((bits >> 3) % 80) / 100) + math.sin(phase) * side * 0.04,
      );
      final radius = side * (0.45 + ((bits >> 5) % 30) / 100);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.softLight
          ..shader = RadialGradient(colors: [p.glows[i], p.glows[i].withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.p != p || old.hash != hash;
}
