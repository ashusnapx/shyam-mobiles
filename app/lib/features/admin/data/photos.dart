import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Bigger files are refused before compressing (a phone photo is 2–8 MB).
const maxPhotoBytes = 15 * 1024 * 1024;

const fullSide = 1600; // longest side of what customers see
const fullQuality = 80;
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

/// Reads a picked file, refusing big ones before they're loaded into memory.
Future<Uint8List> readPhoto(XFile file) async {
  final size = await file.length();
  if (size > maxPhotoBytes) throw FormatException(_tooBig(size));
  return file.readAsBytes();
}

String _tooBig(int bytes) => 'That photo is ${formatBytes(bytes)}. Pick one under 15 MB.';

/// A photo ready to upload: WebP full + thumb, upright, with no metadata.
typedef PreparedPhoto = ({Uint8List full, Uint8List thumb, int originalBytes});

/// Refuses big files and non-images, then makes the full photo and its thumb.
Future<PreparedPhoto> preparePhoto(Uint8List original) async {
  if (original.length > maxPhotoBytes) {
    throw FormatException(_tooBig(original.length));
  }
  final size = await imageSizeOf(original);
  if (size == null) throw const FormatException('That file isn’t a photo. Pick a JPEG, PNG or WebP image.');
  final Uint8List full, thumb;
  try {
    full = await _webp(original, size, fullSide, fullQuality);
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
