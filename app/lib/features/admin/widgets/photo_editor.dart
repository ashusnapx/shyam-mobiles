import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_cropper/image_cropper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';

/// Brightness and contrast (each −1…1) as a colour matrix: contrast pivots on mid-grey, brightness shifts up to ±40.
List<double> adjustMatrix(double brightness, double contrast) {
  final c = 1 + contrast * 0.4;
  final b = brightness * 40 + 128 * (1 - c);
  return [c, 0, 0, 0, b, 0, c, 0, 0, b, 0, 0, c, 0, b, 0, 0, 0, 1, 0];
}

/// Staff's look at a product photo after the automatic clean-up (photos.dart autoProductPhoto): crop & straighten,
/// brightness, contrast, and the background back when the cut-out took too much. [auto] null: no product was found,
/// so it starts from [upright]. Pops with the photo to upload as it is, or null when closed.
Future<Uint8List?> editProductPhoto(BuildContext context, {required Uint8List upright, Uint8List? auto}) =>
    Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PhotoEditor(upright: upright, auto: auto)),
    );

class PhotoEditor extends StatefulWidget {
  const PhotoEditor({super.key, required this.upright, this.auto});

  final Uint8List upright;
  final Uint8List? auto;

  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  late bool _cutout = widget.auto != null;
  Uint8List? _cropped; // of the current base; dropped when the background switch changes the base
  double _brightness = 0, _contrast = 0;
  bool _busy = false;

  Uint8List get _base => _cropped ?? (_cutout ? widget.auto! : widget.upright);

  Future<void> _crop() async {
    final c = Theme.of(context).colorScheme;
    setState(() => _busy = true);
    final dir = await Directory.systemTemp.createTemp('crop');
    try {
      final source = File('${dir.path}/photo.png');
      await source.writeAsBytes(_base);
      final out = await ImageCropper().cropImage(
        sourcePath: source.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1), // every shop photo is square
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop & straighten',
            toolbarColor: c.surface,
            toolbarWidgetColor: c.onSurface,
            statusBarLight: true,
            activeControlsWidgetColor: BrandColors.peacock,
            lockAspectRatio: true,
          ),
        ],
      );
      if (out != null && mounted) {
        final bytes = await File(out.path).readAsBytes();
        setState(() => _cropped = bytes);
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Couldn’t open the crop screen. Try again.');
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    if (_brightness == 0 && _contrast == 0) return Navigator.pop(context, _base);
    setState(() => _busy = true);
    final image = (await (await ui.instantiateImageCodec(_base)).getNextFrame()).image;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(
        image, Offset.zero, Paint()..colorFilter = ColorFilter.matrix(adjustMatrix(_brightness, _contrast)));
    final out = await recorder.endRecording().toImage(image.width, image.height);
    final png = (await out.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose();
    out.dispose();
    if (mounted) Navigator.pop(context, png);
  }

  void _reset() => setState(() {
        _cutout = widget.auto != null;
        _cropped = null;
        _brightness = 0;
        _contrast = 0;
      });

  Widget _slider(String label, IconData icon, double value, ValueChanged<double> onChanged) => Row(children: [
        Icon(icon, size: IconSizes.sm),
        const SizedBox(width: Space.sm),
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: -1, max: 1, divisions: 20, label: '${(value * 100).round()}', onChanged: _busy ? null : onChanged),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit photo'),
        actions: [TextButton(onPressed: _busy ? null : _reset, child: const Text('Reset to auto'))],
      ),
      bottomNavigationBar: StickyBar(
        child: FilledButton(onPressed: _busy ? null : _done, child: const Text('Use this photo')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: ColoredBox(
                color: c.surfaceContainer,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(adjustMatrix(_brightness, _contrast)),
                  child: Image.memory(_base, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remove background'),
            subtitle: Text(widget.auto == null
                ? 'No product found in this photo. Crop it instead.'
                : 'Done on this phone, free. Turn off if part of the product is missing.'),
            value: _cutout,
            onChanged: widget.auto == null || _busy
                ? null
                : (v) => setState(() {
                      _cutout = v;
                      _cropped = null;
                    }),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _crop,
            icon: const Icon(PhosphorIconsRegular.crop),
            label: const Text('Crop & straighten'),
          ),
          const SizedBox(height: Space.md),
          _slider('Brightness', PhosphorIconsRegular.sun, _brightness, (v) => setState(() => _brightness = v)),
          _slider('Contrast', PhosphorIconsRegular.circleHalf, _contrast, (v) => setState(() => _contrast = v)),
          Text('Cropped, straightened and evened out automatically. Change only what looks off.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
