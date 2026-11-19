import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Short, true, useful phone and shop facts for the slow-load view. Plain English; nothing medical or legal, no
/// claims about other shops.
const moFacts = [
  'Dial *#06# to see your phone’s IMEI number.',
  'The IMEI is also on the phone’s box and in Settings, under About phone.',
  'Dual-SIM phones have two IMEI numbers, one for each SIM slot.',
  'Keep your bill and the box: warranty claims need them.',
  'Not sure of your phone model? Look in Settings, under About phone.',
  'Dial 112 for emergency help anywhere in India.',
  'A tempered glass guard costs far less than a new screen.',
  'A camera lens guard keeps the rear cameras free of scratches.',
  'A case with raised edges protects the camera when the phone lies on its back.',
  'A flip cover protects the screen while the phone is in your bag.',
  'Matte screen guards cut glare; glossy ones look sharper.',
  'Heat ages a battery faster, so don’t charge your phone under a pillow.',
  'Keeping the battery between 20% and 80% is gentler on it.',
  'Lower screen brightness is one of the easiest ways to save battery.',
  'Dark mode saves battery on phones with AMOLED or OLED screens.',
  'Turn off Bluetooth and location when you don’t need them to save a little battery.',
  'A phone charges a little faster in airplane mode.',
  'A charger’s watts (W) tell you how fast it can charge, if your phone supports that speed.',
  'A fast charger only charges fast with a cable rated for that speed.',
  'Most new phones charge over USB-C.',
  'A power bank’s mAh number is how much charge it holds: bigger means more top-ups.',
  'If your phone gets wet, switch it off and don’t charge it until it’s dry.',
  'Water-resistant isn’t waterproof: IP ratings are tested in fresh water, not the sea or a pool.',
  'Most phone warranties cover manufacturing faults, not water or drop damage.',
  'Clean the charging port gently with a soft, dry brush, never a pin.',
  'Keep your phone’s software updated: updates fix security problems.',
  'Turn on Find My Device (Android) or Find My (iPhone) to locate a lost phone.',
  'Back up your photos before a repair or a reset.',
  'Take out your SIM and memory card before handing a phone in for repair.',
  'Sign out of your Google or Apple account before selling or exchanging an old phone.',
  'Factory reset an old phone before you exchange or sell it.',
  'Restarting your phone now and then can clear apps that are stuck.',
  'Photos and WhatsApp media fill a phone fast: check the storage before you buy.',
  'To use 5G you need a 5G phone and 5G coverage where you are.',
  'Wi-Fi calling helps indoors where the mobile signal is weak, if your phone and SIM support it.',
  'An eSIM gives you a mobile plan without a SIM card, on phones that support it.',
  'Dual-SIM phones let you keep separate numbers for work and home.',
  'We can arrange covers and glass for your exact phone model, even a brand-new one.',
  'Can’t find something in the app? Ask us on WhatsApp.',
  'A screen guard goes on best over a clean, dust-free screen.',
];

/// "Mor", the shop's pixel-art peacock, bobbing and blinking above a random [moFacts] line: the product page's
/// slow-load view. Shows nothing for the first [delay] so a fast load never flashes it; still with reduced motion.
class MascotLoader extends StatefulWidget {
  const MascotLoader({super.key, this.delay = const Duration(milliseconds: 400)});

  final Duration delay;

  @override
  State<MascotLoader> createState() => _MascotLoaderState();
}

class _MascotLoaderState extends State<MascotLoader> with SingleTickerProviderStateMixin {
  final _fact = moFacts[math.Random().nextInt(moFacts.length)];
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final Timer _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () => setState(() => _shown = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.expand();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading. $_fact',
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(size: const Size.square(112), painter: _MorPainter(still ? null : _c)),
              const SizedBox(height: Space.lg),
              Text('Did you know?', style: t.labelLarge?.copyWith(color: BrandColors.peacockInk)),
              const SizedBox(height: Space.xs),
              Text(_fact, textAlign: TextAlign.center, style: t.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mor in the logo's pixel-feather style: one dot per cell. W/K the eye, closed (feathered over) during a blink.
class _MorPainter extends CustomPainter {
  _MorPainter(this.t) : super(repaint: t);

  final Animation<double>? t; // 0 → 1 per loop; null: still

  static const _map = [
    '....S....S........',
    '...GSG..GSG...G.G.',
    '.S..E....E....T.T.',
    'GSG..E..E....TTTT.',
    '.E....EE....TTWKTO',
    '..EE..EE..E..TTTT.',
    '....EEEEEE....TT..',
    '.S...EEEE....TTT..',
    'GSGEE.EEEE..TTTT..',
    '.E..EEEEEETTTTTT..',
    '...EEEEEEETTTTTT..',
    '.......EEETTTTT...',
    '..........TTTT....',
    '...........O.O....',
    '..........OO.OO...',
  ];

  static const _colors = {
    'T': BrandColors.peacock,
    'E': BrandColors.emerald,
    'G': BrandColors.logoGold,
    'S': BrandColors.sky,
    'W': Colors.white,
    'K': BrandColors.ink,
    'O': BrandColors.saffron,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final v = t?.value ?? 0;
    final cell = size.width / 18;
    final blink = v > 0.9 && v < 0.95;
    canvas.translate(0, math.sin(v * 2 * math.pi) * cell * 0.4 + (size.height - cell * _map.length) / 2);
    final paint = Paint();
    for (final (y, row) in _map.indexed) {
      for (var x = 0; x < row.length; x++) {
        var ch = row[x];
        if (ch == '.') continue;
        if (blink && (ch == 'W' || ch == 'K')) ch = 'T';
        final centre = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        canvas.drawCircle(centre, cell * 0.42, paint..color = _colors[ch]!);
      }
    }
  }

  @override
  bool shouldRepaint(_MorPainter old) => old.t != t;
}
