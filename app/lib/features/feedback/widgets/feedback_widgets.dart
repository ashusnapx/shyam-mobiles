import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/input.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../data/feedback.dart';

/// Five tappable stars (48 dp each), filled up to [value]. Null [onChanged]: just shows the rating.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.onChanged, this.size = 28});

  final int? value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 0;
    if (onChanged == null) {
      return Semantics(
        label: value == null ? 'Not rated' : '$v of 5 stars',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= v ? PhosphorIconsFill.star : PhosphorIconsRegular.star, size: size, color: BrandColors.gold),
        ]),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i star${i == 1 ? '' : 's'}',
            isSelected: i <= v,
            onPressed: () => onChanged!(i),
            icon: Icon(i <= v ? PhosphorIconsFill.star : PhosphorIconsRegular.star, size: size, color: BrandColors.gold),
          ),
      ],
    );
  }
}

/// The feedback sheet: stars, an optional comment (≤ 1000), Send. Pops true once sent. [kinds] with more than one
/// entry adds a choice of what it's about (Account → Send feedback). The route it was opened from goes along.
Future<bool> showFeedbackSheet(
  BuildContext context, {
  required String title,
  required List<FeedbackKind> kinds,
  String? orderId,
  String? repairId,
  String? productId,
  int? rating,
  String message = '',
  String hint = 'Tell us more (optional)',
}) async {
  final screen = feedbackScreen(GoRouter.maybeOf(context)?.state.uri);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FeedbackSheet(
      title: title,
      kinds: kinds,
      orderId: orderId,
      repairId: repairId,
      productId: productId,
      rating: rating,
      message: message,
      hint: hint,
      screen: screen,
    ),
  );
  if (sent == true && context.mounted) showMessage(context, 'Thank you. The shop reads every message.');
  return sent == true;
}

class FeedbackSheet extends ConsumerStatefulWidget {
  const FeedbackSheet({
    super.key,
    required this.title,
    required this.kinds,
    this.orderId,
    this.repairId,
    this.productId,
    this.rating,
    this.message = '',
    this.hint = 'Tell us more (optional)',
    this.screen,
  });

  final String title;
  final List<FeedbackKind> kinds;
  final String? orderId;
  final String? repairId;
  final String? productId;
  final int? rating;
  final String message;
  final String hint;
  final String? screen;

  @override
  ConsumerState<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<FeedbackSheet> {
  late int? _rating = widget.rating;
  late final _message = TextEditingController(text: widget.message);
  late FeedbackKind _kind = widget.kinds.first;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final message = tidy(_message.text, multiline: true);
    // the DB keeps a row only with a rating or some words
    if (_rating == null && message.isEmpty) return setState(() => _error = 'Pick a star or write a few words.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(feedbackApiProvider).send(
            kind: _kind,
            rating: _rating,
            message: message,
            orderId: widget.orderId,
            repairId: widget.repairId,
            productId: widget.productId,
            screen: widget.screen,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(widget.title, style: t.titleLarge)),
            const SizedBox(height: Space.md),
            if (widget.kinds.length > 1) ...[
              PickerField<FeedbackKind>(
                label: 'About',
                options: widget.kinds,
                labelOf: (k) => k == FeedbackKind.bug ? 'Something isn’t working' : 'An idea or a comment',
                initialValue: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(height: Space.md),
            ],
            Center(child: StarRating(value: _rating, onChanged: _busy ? null : (r) => setState(() => _rating = r))),
            const SizedBox(height: Space.md),
            TextField(
              controller: _message,
              decoration: InputDecoration(
                labelText: widget.hint,
                alignLabelWithHint: true,
                counter: LengthCounter(_message, maxFeedbackMessage),
              ),
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: textInput(maxFeedbackMessage, multiline: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
            ],
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "How was your order?": five stars and the rating already given, if any. Tapping a star (or "Change") opens the
/// feedback sheet with it; rating again replaces the old rating. Give it [orderId] for an order, [repairId] for a
/// repair (exactly one), and show it once the order is delivered or the repair completed.
class RateCard extends ConsumerWidget {
  const RateCard({super.key, required this.title, this.orderId, this.repairId})
      : assert((orderId == null) != (repairId == null), 'rate an order or a repair');

  final String title; // "How was your order?"
  final String? orderId;
  final String? repairId;

  FeedbackKind get _kind => orderId != null ? FeedbackKind.order : FeedbackKind.repair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final key = (_kind, orderId ?? repairId!);
    final mine = ref.watch(myFeedbackProvider(key)).value;
    Future<void> rate(int? stars) async {
      final sent = await showFeedbackSheet(
        context,
        title: title,
        kinds: [_kind],
        orderId: orderId,
        repairId: repairId,
        rating: stars ?? mine?.rating,
        message: mine?.message ?? '',
      );
      if (sent) ref.invalidate(myFeedbackProvider(key));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              mine?.rating == null ? 'Tap a star. It helps the shop and other buyers.' : 'Thanks for rating. Tap to change it.',
              style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StarRating(value: mine?.rating, onChanged: rate),
                if (mine != null) TextButton(onPressed: () => rate(null), child: const Text('Change')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Report a problem with this listing" at the foot of a product page: a wrong price, photo or spec.
class ReportListingLink extends StatelessWidget {
  const ReportListingLink({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showFeedbackSheet(
              context,
              title: 'Report a problem with this listing',
              kinds: const [FeedbackKind.product],
              productId: productId,
              hint: 'What’s wrong? A price, photo or detail',
            ),
            icon: const Icon(PhosphorIconsRegular.flag, size: 18),
            label: const Text('Report a problem with this listing'),
          ),
        ),
      );
}
