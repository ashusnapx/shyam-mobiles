import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'env.dart';
import 'supabase.dart' show publicImageUrl;
import 'theme/generative.dart';
import 'theme/tokens.dart';
import 'widgets/widgets.dart';

/// Share to Instagram / Facebook Story: a 1080x1920 card of a product, handed to the app by MainActivity's
/// shyam_mobiles/stories channel. No buttons without META_APP_ID (Meta asks for it) or without the app.
enum StoryApp {
  instagram('Instagram', PhosphorIconsFill.instagramLogo, BrandColors.instagram),
  facebook('Facebook', PhosphorIconsFill.facebookLogo, BrandColors.facebook);

  const StoryApp(this.brand, this.icon, this.color);

  final String brand;
  final IconData icon;
  final Color color;

  String get label => 'Share to $brand Story';
}

/// What the card shows: [photo] is a product-images key; [link] the share link, or how to find the app.
typedef Story = ({String id, String name, String price, String? photo, String link});

const _channel = MethodChannel('shyam_mobiles/stories');

/// The story apps on this phone: none without META_APP_ID, off Android, or when neither is installed.
final storyAppsProvider = FutureProvider<List<StoryApp>>((ref) async {
  if (Env.metaAppId.isEmpty) return const [];
  try {
    final names = await _channel.invokeListMethod<String>('installed') ?? const [];
    return [for (final a in StoryApp.values) if (names.contains(a.name)) a];
  } catch (_) {
    return const [];
  }
});

bool _sharing = false; // a second tap while the card renders does nothing

/// Draws [story] off screen, saves it as a PNG in the cache and opens [app]'s story editor with it.
Future<void> shareStory(BuildContext context, StoryApp app, Story story) async {
  if (_sharing) return;
  _sharing = true;
  try {
    final png = await _render(context, story);
    final ok = await _channel.invokeMethod<bool>('share', {'app': app.name, 'png': png, 'appId': Env.metaAppId});
    if (ok != true) throw StateError('${app.name} gone');
  } catch (_) {
    if (context.mounted) showMessage(context, 'Couldn’t open ${app.brand}. Try again.');
  } finally {
    _sharing = false;
  }
}

/// [StoryCard] at 360x640 beside the screen (never on it), captured at 3x: 1080x1920.
Future<Uint8List> _render(BuildContext context, Story story) async {
  final photo = story.photo == null ? null : CachedNetworkImageProvider(publicImageUrl(story.photo!));
  if (photo != null) await precacheImage(photo, context); // a failed photo still renders: the card shows a phone icon
  if (!context.mounted) throw StateError('screen closed');
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -2000,
      top: 0,
      width: 360,
      height: 640,
      child: RepaintBoundary(key: key, child: MediaQuery.withNoTextScaling(child: StoryCard(story, photo: photo))),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 3);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// The story itself: the product's deep colours, its photo on white, name, price, the shop and the link. The middle
/// holds everything that matters, clear of Instagram's own bars at the top and bottom.
class StoryCard extends StatelessWidget {
  const StoryCard(this.story, {super.key, this.photo});

  final Story story;
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const white = Colors.white;
    return Material(
      child: AuroraBackground(
        palette: deepPalette(story.id), // white passes 7:1 on every stop; goldSoft well over 4.5:1
        seed: story.id,
        still: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 72, 28, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 40, onDark: true),
              const SizedBox(height: Space.lg),
              // the photo takes what the words leave: a long name never pushes the shop off the card
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: white, borderRadius: BorderRadius.circular(Radii.hero)),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.lg),
                        child: photo == null
                            ? const Icon(PhosphorIconsLight.deviceMobile, size: 96, color: BrandColors.mist)
                            : Image(image: photo!, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(story.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineSmall?.copyWith(color: white, fontWeight: FontWeight.w700)),
              const SizedBox(height: Space.xs),
              Text(story.price, style: t.headlineMedium?.copyWith(color: BrandColors.goldSoft, fontWeight: FontWeight.w800)),
              const SizedBox(height: Space.lg),
              Text('Shyam Mobiles · Waidhan', style: t.titleMedium?.copyWith(color: white, fontWeight: FontWeight.w700)),
              Text(story.link, maxLines: 2, style: t.bodyMedium?.copyWith(color: white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Share to Instagram Story", "Share to Facebook Story": a tile per story app on this phone, nothing without one.
/// [onPick] replaces sharing straight away (the share sheet closes first, then shares).
class StoryTiles extends ConsumerWidget {
  const StoryTiles(this.story, {super.key, this.onPick, this.divided = false});

  final Story story;
  final ValueChanged<StoryApp>? onPick;
  final bool divided; // a divider above, inside a card of other rows

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(storyAppsProvider).value ?? const [];
    if (apps.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (divided) const Divider(),
        for (final a in apps)
          ListTile(
            leading: SizedBox.square(dimension: 36, child: Center(child: Icon(a.icon, size: 24, color: a.color))),
            title: Text(a.label),
            onTap: () => onPick != null ? onPick!(a) : shareStory(context, a, story),
          ),
      ],
    );
  }
}
