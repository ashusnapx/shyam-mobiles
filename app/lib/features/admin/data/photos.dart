import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Any camera photo is taken as it is and compressed here; only something no camera makes (a video picked by mistake)
/// is turned away, so a ₹10k phone never tries to load it.
const maxPhotoBytes = 100 * 1024 * 1024;

/// What a stored photo may weigh: under the bucket's 1 MB cap (migration 20261030000700) with room to spare.
const photoBudgetBytes = 900 * 1024;

const fullSide = 1600; // longest side of what customers see
const fullQuality = 80;

/// Tries, best first, until the photo fits [photoBudgetBytes]: quality comes down a little before size does, since
/// WebP at 70-ish still looks the same on a phone screen. Nearly every photo fits on the first try (20–300 KB).
const photoSteps = [(fullSide, fullQuality), (fullSide, 72), (fullSide, 64), (1400, 64), (1200, 60), (1000, 56)];

const thumbSide = 480; // lists and data-saver mode
const thumbQuality = 70;

/// flutter_image_compress keeps the *shorter* side at or above minWidth/minHeight, so for "longest side ≤ [maxSide]"
/// both get [minSide] = short × maxSide / long. It first decodes at 1/[inSampleSize] (a power of two that keeps the
/// longest side ≥ [maxSide]), so a 50 MP photo isn't decoded at full size (200 MB) on a 2 GB phone.
/// [width]/[height] are what comes out (±1 px of the decoder's rounding).
({int inSampleSize, int minSide, int width, int height}) photoPlan(int width, int height, int maxSide) {
  final long = max(width, height);
  if (long <= maxSide) return (inSampleSize: 1, minSide: min(width, height), width: width, height: height);
  var sample = 1;
  while (long ~/ (sample * 2) >= maxSide) {
    sample *= 2;
  }
  final w = width ~/ sample, h = height ~/ sample;
  final short = min(w, h), sampledLong = max(w, h);
  final minSide = max(1, short * maxSide ~/ sampledLong);
  // the plugin's scale is short / minSide; each side is divided by it and truncated
  int out(int side) => side * minSide ~/ short;
  return (inSampleSize: sample, minSide: minSide, width: out(w), height: out(h));
}

/// "4.2 MB", "180 KB", "512 B".
String formatBytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : bytes >= 1024
        ? '${(bytes / 1024).round()} KB'
        : '$bytes B';

/// Reads a picked file, refusing only what can't be a photo before it's loaded into memory.
Future<Uint8List> readPhoto(XFile file) async {
  checkPhotoSize(await file.length());
  return file.readAsBytes();
}

void checkPhotoSize(int bytes) {
  if (bytes > maxPhotoBytes) {
    throw FormatException('That file is ${formatBytes(bytes)}, too big to be a photo. Pick a photo instead.');
  }
}

/// The first of [photoSteps] whose result fits [budget]; [encode] makes the WebP for (longest side, quality).
Future<Uint8List> fitBudget(Future<Uint8List> Function(int side, int quality) encode,
    {int budget = photoBudgetBytes}) async {
  var out = Uint8List(0);
  for (final (side, quality) in photoSteps) {
    out = await encode(side, quality);
    if (out.length <= budget) return out;
  }
  // shortcut: a 1000 px WebP at 56 over 900 KB is pathological noise; upload it and let the server's 1 MB cap decide
  return out;
}

/// A photo ready to upload: WebP full + thumb, upright, with no metadata.
typedef PreparedPhoto = ({Uint8List full, Uint8List thumb, int originalBytes});

/// Refuses non-images, then makes the full photo (always under [photoBudgetBytes]) and its thumb.
Future<PreparedPhoto> preparePhoto(Uint8List original) async {
  checkPhotoSize(original.length);
  final size = await imageSizeOf(original);
  if (size == null) throw const FormatException('That file isn’t a photo. Pick a JPEG, PNG or WebP image.');
  final Uint8List full, thumb;
  try {
    full = await fitBudget((side, quality) => _webp(original, size, side, quality));
    // from the 1600 px WebP: much faster than decoding the camera original again
    thumb = await _webp(full, await imageSizeOf(full) ?? size, thumbSide, thumbQuality);
  } catch (_) {
    throw const FormatException('Couldn’t read that photo. It may be damaged. Try another one.');
  }
  if (full.isEmpty || thumb.isEmpty) throw const FormatException('Couldn’t read that photo. Try another one.');
  return (full: full, thumb: thumb, originalBytes: original.length);
}

/// Pixel size from the file header, without decoding it. Null when it isn't an image the phone can read.
Future<(int, int)?> imageSizeOf(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final d = await ui.ImageDescriptor.encoded(buffer);
    final size = (d.width, d.height);
    d.dispose();
    buffer.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _webp(Uint8List bytes, (int, int) size, int maxSide, int quality) {
  final plan = photoPlan(size.$1, size.$2, maxSide);
  return FlutterImageCompress.compressWithList(
    bytes,
    minWidth: plan.minSide,
    minHeight: plan.minSide,
    inSampleSize: plan.inSampleSize,
    quality: quality,
    format: CompressFormat.webp,
    autoCorrectionAngle: true, // turn it upright from the EXIF orientation, then the tag can go
    // Never copy EXIF: phone photos carry GPS, which would publish where the shop (or a staff member's home) is.
    keepExif: false,
  );
}
