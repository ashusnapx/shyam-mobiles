import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/widgets/store_photos.dart';

/// Shop phone, WhatsApp, directions, address and hours from `store_settings` (Account, Repairs). Shown signed in and
/// out. [whatsAppText] prefills the chat.
class StoreCard extends ConsumerWidget {
  const StoreCard({super.key, this.whatsAppText = 'Hi, I need help with my account'});

  final String whatsAppText;

  static const _placeholder = StoreSettings(
    deliveryFeePaise: 0,
    freeDeliveryMinPaise: 0,
    codEnabled: false,
    codMaxPaise: 0,
    storePhone: '+919999999999',
    storeAddress: 'Shop address goes here, City 000000',
    storeHours: '10 am – 9 pm',
    repairNote: '',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storeSettingsProvider);
    if (settings.hasError && !settings.hasValue) {
      return Card(
        child: ListTile(
          leading: const Icon(PhosphorIconsRegular.cloudX),
          title: const Text('Couldn’t load the shop’s details'),
          subtitle: Text(friendlyError(settings.error!)),
          trailing: TextButton(onPressed: () => ref.invalidate(storeSettingsProvider), child: const Text('Retry')),
        ),
      );
    }
    final s = settings.value ?? _placeholder;
    final phone = s.storePhone;
    return Skeletonizer(
      enabled: !settings.hasValue,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StoreHero(settings: s, onReviews: s.mapsListingUri == null ? null : () => openUri(context, s.mapsListingUri!)),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.phone),
              title: const Text('Call shop'),
              subtitle: Text(displayPhone(phone)),
              onTap: () => openUri(context, telUri(phone)),
            ),
            if (s.mapsDestination.isNotEmpty)
              ListTile(
                leading: const Icon(PhosphorIconsRegular.navigationArrow),
                title: const Text('Directions'),
                subtitle: const Text('Open in Google Maps'),
                onTap: () => openUri(context, directionsUri(s.mapsDestination)),
              ),
            ListTile(
              leading: const WhatsAppIcon(),
              title: const Text('WhatsApp the shop'),
              onTap: () => openUri(context, whatsAppUri(phone, text: whatsAppText)),
            ),
            if (s.returnsPolicy.isNotEmpty)
              ListTile(
                leading: const Icon(PhosphorIconsRegular.shieldCheck),
                title: const Text('Returns & warranty'),
                onTap: () => showReturnsSheet(context, s),
              ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}

/// The shop at the top of the store card: its own photo (Admin > Settings > Shop photos) under a dark gradient
/// with name, hours and address. Google's listing photos would need the paid Places API with attribution, so
/// we show the owner's photos and link to Google for reviews instead.
class _StoreHero extends StatelessWidget {
  const _StoreHero({required this.settings, required this.onReviews});

  final StoreSettings settings;
  final VoidCallback? onReviews;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final photos = settings.storePhotos;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [BrandColors.graphite, Colors.black],
                ),
              ),
              child: Align(alignment: Alignment(0.75, -0.35), child: BrandMark(size: 72, onDark: true)),
            )
          else
            Semantics(
              button: true,
              label: 'Photos of the shop, ${photos.length}',
              child: GestureDetector(
                onTap: () => openStorePhotoViewer(context, photos, 0),
                child: LayoutBuilder(
                  builder: (context, box) => CachedNetworkImage(
                    imageUrl: publicImageUrl(photos.first),
                    fit: BoxFit.cover,
                    memCacheWidth: (box.maxWidth * dpr).round(),
                    errorWidget: (_, _, _) => const ColoredBox(color: BrandColors.graphite),
                  ),
                ),
              ),
            ),
          // Legibility: transparent at the top, near-black where the text sits.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.25, 1],
                  colors: [Color(0x00000000), Color(0xD9000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: Space.lg,
            right: Space.lg,
            bottom: Space.md,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shyam Mobiles', style: t.displaySmall?.copyWith(fontSize: 22, color: Colors.white)),
                  if (settings.storeHours.isNotEmpty)
                    Text('Open ${settings.storeHours}', style: t.bodySmall?.copyWith(color: Colors.white)),
                  if (settings.storeAddress.isNotEmpty)
                    Text(settings.storeAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                ],
              ),
            ),
          ),
          if (onReviews != null)
            Positioned(
              top: Space.sm,
              right: Space.sm,
              child: ActionChip(
                onPressed: onReviews,
                avatar: const Icon(PhosphorIconsBold.star, size: 14, color: Colors.white),
                label: const Text('Google reviews'),
                labelStyle: t.labelSmall?.copyWith(color: Colors.white),
                backgroundColor: Colors.black.withValues(alpha: 0.45),
                side: BorderSide.none,
                tooltip: 'Open Shyam Mobile Center on Google Maps',
              ),
            ),
          if (photos.length > 1)
            Positioned(
              top: Space.sm,
              left: Space.sm,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(Radii.sm)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
                    child: Text('1 / ${photos.length}', style: t.labelSmall?.copyWith(color: Colors.white)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
