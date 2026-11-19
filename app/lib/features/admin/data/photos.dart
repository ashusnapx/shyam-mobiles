import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';

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

/// A photo ready to upload: WebP full + thumb, upright, with no metadata; [cut] the product alone when asked for.
typedef PreparedPhoto = ({Uint8List full, Uint8List thumb, int originalBytes, Uint8List? cut});

/// Refuses non-images, then makes the full photo (always under [photoBudgetBytes]) and its thumb; with [cut], also
/// its cut-out ([cutoutOf]), or none when that fails. [studio] (product photos): when the cut-out works, the full
/// photo and thumb are [studioOf] it instead, so every product photo in the shop looks the same.
Future<PreparedPhoto> preparePhoto(Uint8List original, {bool cut = false, bool studio = false}) async {
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
  final cutout = cut || studio ? await cutoutOf(full) : null;
  if (studio && cutout != null) {
    final square = await studioOf(cutout);
    final shop = await fitBudget((side, quality) => _webp(square, (studioSide, studioSide), side, quality));
    final shopThumb = await _webp(shop, (studioSide, studioSide), thumbSide, thumbQuality);
    return (full: shop, thumb: shopThumb, originalBytes: original.length, cut: cutout);
  }
  return (full: full, thumb: thumb, originalBytes: original.length, cut: cut ? cutout : null);
}

/// The automatic clean-up of a product photo, before anyone edits it: [upright] the photo turned upright, compressed
/// and without EXIF; [auto] its cut-out on the shop's square ([studioOf]), or null when no product was found.
Future<({Uint8List upright, Uint8List? auto})> autoProductPhoto(Uint8List original) async {
  final upright = (await preparePhoto(original)).full;
  final cut = await cutoutOf(upright);
  return (upright: upright, auto: cut == null ? null : await studioOf(cut));
}

const studioSide = 1200; // the cut-out is at most [cutSide], so no upscaling past it
const studioBackdrop = ui.Color(0xFFFFFFFF); // the product gallery's white
const studioFill = 0.84; // the product's longest side on the square: the same margin on every photo

/// [cut] (a trimmed cut-out) centred on a plain [studioSide] square at [studioFill], as PNG.
Future<Uint8List> studioOf(Uint8List cut) async {
  final image = (await (await ui.instantiateImageCodec(cut)).getNextFrame()).image;
  try {
    const side = studioSide * 1.0;
    final scale = side * studioFill / max(image.width, image.height);
    final dst = ui.Rect.fromCenter(
        center: const ui.Offset(side / 2, side / 2), width: image.width * scale, height: image.height * scale);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawColor(studioBackdrop, ui.BlendMode.src)
      ..drawImageRect(image, ui.Offset.zero & ui.Size(image.width * 1.0, image.height * 1.0), dst,
          ui.Paint()..filterQuality = ui.FilterQuality.high);
    final square = await recorder.endRecording().toImage(studioSide, studioSide);
    final png = (await square.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    square.dispose();
    return png;
  } finally {
    image.dispose();
  }
}

const cutSide = 1200;

/// The product alone on a transparent background: ML Kit subject segmentation on the phone (Play services fetches
/// its model on first use), trimmed to its edges, at most [cutSide] px, WebP with alpha. Null when it can't be made
/// (not Android, model still downloading, nothing found): the photo goes up without one and the app shows the photo.
Future<Uint8List?> cutoutOf(Uint8List photo) async {
  if (!Platform.isAndroid) return null;
  final segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: true,
      enableForegroundConfidenceMask: false,
      enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
    ),
  );
  try {
    final size = await imageSizeOf(photo);
    if (size == null) return null;
    final plan = photoPlan(size.$1, size.$2, cutSide);
    final frame = await (await ui.instantiateImageCodec(photo, targetWidth: plan.width, targetHeight: plan.height)).getNextFrame();
    final rgba = swapRedBlue((await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List());
    final input = InputImage.fromBitmap(bitmap: rgba, width: frame.image.width, height: frame.image.height);
    frame.image.dispose();
    final png = (await segmenter.processImage(input)).foregroundBitmap;
    return png == null ? null : await _trimmed(png);
  } catch (_) {
    return null;
  } finally {
    unawaited(segmenter.close());
  }
}

/// RGBA ⇄ BGRA, in place. google_mlkit_commons 1.0.3 packs fromBitmap's bytes as ARGB ints, which Android's
/// copyPixelsFromBuffer reads as RGBA, so red and blue arrive swapped (a blue box came out orange): swapping them
/// first cancels it out.
Uint8List swapRedBlue(Uint8List rgba) {
  for (var i = 0; i + 2 < rgba.length; i += 4) {
    final r = rgba[i];
    rgba[i] = rgba[i + 2];
    rgba[i + 2] = r;
  }
  return rgba;
}

/// [png] straightened ([tiltOf]), cropped to its visible pixels, its light evened out ([levelsOf]) and encoded as
/// WebP with alpha; null when it is all transparent.
Future<Uint8List?> _trimmed(Uint8List png) async {
  var image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
  try {
    var rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    final tilt = tiltOf(rgba, image.width, image.height);
    if (tilt != 0) {
      final upright = await _rotated(image, -tilt);
      image.dispose();
      image = upright;
      rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    }
    final box = alphaBounds(rgba, image.width, image.height);
    if (box == null) return null;
    final (gain, lift) = levelsOf(rgba);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      box,
      ui.Offset.zero & box.size,
      ui.Paint()
        ..colorFilter = ui.ColorFilter.matrix([gain, 0, 0, 0, lift, 0, gain, 0, 0, lift, 0, 0, gain, 0, lift, 0, 0, 0, 1, 0]),
    );
    final cropped = await recorder.endRecording().toImage(box.width.round(), box.height.round());
    final bytes = (await cropped.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    cropped.dispose();
    return await _webp(bytes, (box.width.round(), box.height.round()), cutSide, 85);
  } finally {
    image.dispose();
  }
}

/// [image] turned by [radians] about its centre, on a canvas big enough for its corners.
Future<ui.Image> _rotated(ui.Image image, double radians) {
  final w = image.width.toDouble(), h = image.height.toDouble();
  final c = cos(radians).abs(), s = sin(radians).abs();
  final nw = (w * c + h * s).ceil(), nh = (w * s + h * c).ceil();
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..translate(nw / 2, nh / 2)
    ..rotate(radians)
    ..drawImage(image, ui.Offset(-w / 2, -h / 2), ui.Paint()..filterQuality = ui.FilterQuality.high);
  return recorder.endRecording().toImage(nw, nh);
}

/// How far (radians, y down) the product's long axis sits off the nearest straight one, from the shape of its opaque
/// pixels (straight RGBA); 0 when it is straight already (under 0.5°), tilted on purpose (over 12°), or too square
/// or round to have a long axis.
double tiltOf(Uint8List rgba, int width, int height) {
  var n = 0;
  var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (var y = 0; y < height; y += 2) {
    final row = y * width * 4;
    for (var x = 0; x < width; x += 2) {
      if (rgba[row + x * 4 + 3] < 128) continue;
      n++;
      sx += x;
      sy += y;
      sxx += x * x;
      syy += y * y;
      sxy += x * y;
    }
  }
  if (n < 100) return 0;
  final mx = sx / n, my = sy / n;
  final a = sxx / n - mx * mx, b = syy / n - my * my, c = sxy / n - mx * my;
  if ((a - b) * (a - b) + 4 * c * c < 0.02 * (a + b) * (a + b)) return 0;
  var off = (0.5 * atan2(2 * c, a - b)) % (pi / 2);
  if (off > pi / 4) off -= pi / 2;
  final degrees = off.abs() * 180 / pi;
  return degrees < 0.5 || degrees > 12 ? 0 : off;
}

/// Gain and lift that stretch the product's brightness from its 1st to its 99th percentile toward the full range
/// (at most 1.4×), so a photo taken in dim shop light comes out like the rest; (1, 0) when there is nothing to fix.
(double, double) levelsOf(Uint8List rgba) {
  final counts = List.filled(256, 0);
  var n = 0;
  for (var i = 0; i + 3 < rgba.length; i += 8) {
    if (rgba[i + 3] < 128) continue;
    counts[(rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8]++;
    n++;
  }
  if (n < 100) return (1, 0);
  int at(double share) {
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += counts[v];
      if (seen >= n * share) return v;
    }
    return 255;
  }

  final lo = at(0.01), hi = at(0.99);
  if (hi - lo < 32) return (1, 0); // one flat colour: nothing to stretch
  final gain = min(255 / (hi - lo), 1.4);
  return (gain, -lo * gain);
}

/// The box around the pixels whose alpha is above [threshold] (straight RGBA, row by row); null when there are none.
ui.Rect? alphaBounds(Uint8List rgba, int width, int height, {int threshold = 8}) {
  var left = width, top = height, right = -1, bottom = -1;
  for (var y = 0; y < height; y++) {
    final row = y * width * 4;
    for (var x = 0; x < width; x++) {
      if (rgba[row + x * 4 + 3] <= threshold) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      bottom = y;
    }
  }
  return right < 0 ? null : ui.Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
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

/// A JPEG copy for Instagram / Facebook posts, which take no WebP: at most 1080 px wide, quality 85, upright, no EXIF.
Future<Uint8List> socialJpeg(Uint8List original) async {
  final size = await imageSizeOf(original);
  if (size == null) throw const FormatException('That file isn’t a photo. Pick a JPEG, PNG or WebP image.');
  return _webp(original, size, socialMaxSide(size.$1, size.$2), 85, format: CompressFormat.jpeg);
}

const socialWidth = 1080;

/// [photoPlan] caps the longest side; for a tall photo the cap is set so its width lands on [socialWidth].
int socialMaxSide(int width, int height) => width >= height ? socialWidth : socialWidth * height ~/ width;

Future<Uint8List> _webp(Uint8List bytes, (int, int) size, int maxSide, int quality,
    {CompressFormat format = CompressFormat.webp}) {
  final plan = photoPlan(size.$1, size.$2, maxSide);
  return FlutterImageCompress.compressWithList(
    bytes,
    minWidth: plan.minSide,
    minHeight: plan.minSide,
    inSampleSize: plan.inSampleSize,
    quality: quality,
    format: format,
    autoCorrectionAngle: true, // turn it upright from the EXIF orientation, then the tag can go
    // Never copy EXIF: phone photos carry GPS, which would publish where the shop (or a staff member's home) is.
    keepExif: false,
  );
}
