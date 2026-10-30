import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../errors.dart';
import '../input.dart';
import '../theme/tokens.dart';
import 'widgets.dart';

/// The one way to choose from a list anywhere in the app (no Material dropdowns: their menus overflow at
/// large text and can't be searched). A sheet with search for long lists, a ticked, scrollable list that
/// fits any screen, and an optional "Add …" row when nothing matches.
/// Null when dismissed; otherwise a record with the choice, which may itself be null (an "Any" option).
Future<(T?,)?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T?, String)> options,
  T? selected,
  String? searchHint,
  Future<T?> Function(String name)? onCreate,
  String createLabel = 'Add',
  String Function(String typed)? createName,
}) =>
    showModalBottomSheet<(T?,)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PickerSheet<T>(
        title: title,
        options: options,
        selected: selected,
        searchHint: searchHint,
        onCreate: onCreate,
        createLabel: createLabel,
        createName: createName,
      ),
    );

/// [showPickerSheet] for several values: rows tick and untick, Done returns the ticked set. Null when dismissed.
Future<Set<T>?> showMultiPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  Set<T> selected = const {},
  String? searchHint,
}) =>
    showModalBottomSheet<Set<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PickerSheet<T>(
        title: title,
        options: options,
        selected: null,
        multi: selected,
        searchHint: searchHint,
        onCreate: null,
        createLabel: '',
        createName: null,
      ),
    );

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchHint,
    required this.onCreate,
    required this.createLabel,
    required this.createName,
    this.multi,
  });

  final String title;
  final List<(T?, String)> options;
  final T? selected;
  final Set<T>? multi; // non-null: several can be ticked
  final String? searchHint;
  final Future<T?> Function(String name)? onCreate;
  final String createLabel;
  final String Function(String typed)? createName; // how the new entry will be saved, for the preview

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  final _query = TextEditingController();
  bool _creating = false;
  late final Set<T>? _ticked = widget.multi == null ? null : {...widget.multi!};

  bool _isSelected(T? value) => _ticked?.contains(value) ?? value == widget.selected;

  void _pick(T? value) {
    final ticked = _ticked;
    if (ticked == null) return Navigator.pop(context, (value,));
    setState(() => ticked.contains(value) ? ticked.remove(value) : ticked.add(value as T));
  }

  bool get _searchable => widget.options.length > 7 || widget.onCreate != null;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _query.text.trim();
    setState(() => _creating = true);
    try {
      final created = await widget.onCreate!(name);
      if (mounted && created != null) Navigator.pop(context, (created,));
    } catch (e) {
      if (mounted) showMessage(context, e is FormatException ? e.message : friendlyError(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final q = _query.text.trim().toLowerCase();
    final shown = q.isEmpty ? widget.options : widget.options.where((o) => o.$2.toLowerCase().contains(q)).toList();
    final canCreate = widget.onCreate != null && q.isNotEmpty && !widget.options.any((o) => o.$2.toLowerCase() == q);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Space.lg, 0, _ticked == null ? Space.lg : Space.sm, Space.sm),
              child: Row(
                children: [
                  Expanded(child: Semantics(header: true, child: Text(widget.title, style: t.titleLarge))),
                  if (_ticked case final ticked?)
                    FilledButton(onPressed: () => Navigator.pop(context, ticked), child: Text('Done (${ticked.length})')),
                ],
              ),
            ),
            if (_searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
                child: TextField(
                  controller: _query,
                  autofocus: widget.options.length > 7,
                  textInputAction: TextInputAction.search,
                  inputFormatters: textInput(MaxLen.search),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (shown.length == 1) {
                      _pick(shown.first.$1);
                    } else if (canCreate && !_creating) {
                      _create();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: widget.searchHint ?? 'Search',
                    prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
                    suffixIcon: q.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(PhosphorIconsRegular.xCircle, size: 20),
                            onPressed: () => setState(_query.clear),
                          ),
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.lg),
                children: [
                  for (final (value, label) in shown)
                    ListTile(
                      minTileHeight: 52,
                      title: Text(label),
                      selected: _isSelected(value),
                      selectedColor: c.onSurface,
                      trailing: _isSelected(value) ? const Icon(PhosphorIconsBold.check, size: 18) : null,
                      onTap: () => _pick(value),
                    ),
                  if (shown.isEmpty && !canCreate)
                    Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Text('Nothing matches “${_query.text.trim()}”.',
                          style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                    ),
                  if (canCreate)
                    ListTile(
                      minTileHeight: 52,
                      leading: _creating
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(PhosphorIconsRegular.plusCircle),
                      title: Text('${widget.createLabel} “${(widget.createName ?? (String s) => s)(_query.text.trim())}”'),
                      onTap: _creating ? null : _create,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form field that opens [showPickerSheet]. Values are compared with ==, so pass ids rather than objects.
class PickerField<T> extends FormField<T> {
  PickerField({
    super.key,
    required String label,
    required List<T> options,
    required String Function(T value) labelOf,
    required ValueChanged<T> onChanged,
    super.initialValue,
    super.validator,
    String? helperText,
    String? searchHint,
    Future<T?> Function(String name)? onCreate,
    String createLabel = 'Add',
    String Function(String typed)? createName,
  }) : super(
          builder: (field) {
            final value = field.value;
            Future<void> open() async {
              final picked = await showPickerSheet<T>(
                field.context,
                title: label,
                options: [for (final o in options) (o, labelOf(o))],
                selected: value,
                searchHint: searchHint,
                onCreate: onCreate,
                createLabel: createLabel,
                createName: createName,
              );
              final choice = picked?.$1;
              if (choice == null) return;
              field.didChange(choice);
              onChanged(choice);
            }

            return Semantics(
              button: true,
              label: value == null ? label : '$label, ${labelOf(value)}',
              excludeSemantics: true,
              child: InkWell(
                onTap: open,
                borderRadius: BorderRadius.circular(Radii.md),
                child: InputDecorator(
                  isEmpty: value == null,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: helperText,
                    errorText: field.errorText,
                    suffixIcon: const Icon(PhosphorIconsRegular.caretDown, size: 18),
                  ),
                  child: Text(value == null ? '' : labelOf(value), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            );
          },
        );
}

/// Form field that opens [showMultiPickerSheet]: shows what's ticked ("Samsung, Apple +2 more").
class MultiPickerField<T> extends FormField<Set<T>> {
  MultiPickerField({
    super.key,
    required String label,
    required List<T> options,
    required String Function(T value) labelOf,
    required ValueChanged<Set<T>> onChanged,
    required Set<T> super.initialValue,
    super.validator,
    String? helperText,
    String? searchHint,
  }) : super(
          builder: (field) {
            final value = field.value ?? const {};
            Future<void> open() async {
              final picked = await showMultiPickerSheet<T>(
                field.context,
                title: label,
                options: [for (final o in options) (o, labelOf(o))],
                selected: value,
                searchHint: searchHint,
              );
              if (picked == null) return;
              field.didChange(picked);
              if (field.hasError) field.validate(); // a fixed field drops its error
              onChanged(picked);
            }

            final names = value.map(labelOf).toList();
            final summary = names.length <= 2 ? names.join(', ') : '${names.take(2).join(', ')} +${names.length - 2} more';
            return Semantics(
              button: true,
              label: value.isEmpty ? label : '$label, ${names.join(', ')}',
              excludeSemantics: true,
              child: InkWell(
                onTap: open,
                borderRadius: BorderRadius.circular(Radii.md),
                child: InputDecorator(
                  isEmpty: value.isEmpty,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: helperText,
                    helperMaxLines: 3,
                    errorText: field.errorText,
                    errorMaxLines: 3,
                    suffixIcon: const Icon(PhosphorIconsRegular.caretDown, size: 18),
                  ),
                  child: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
            );
          },
        );
}

/// Filter chip that opens [showPickerSheet]: a caret (or [icon]) marks it as a list, tinted while a filter is set.
class PickerChip extends StatelessWidget {
  const PickerChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fg = selected ? c.onPrimaryContainer : c.onSurface;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      selectedColor: c.primaryContainer,
      side: selected ? BorderSide.none : null,
      avatar: icon == null ? null : Icon(icon, size: 16, color: fg),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Text(label, style: TextStyle(color: fg)),
          if (icon == null) Icon(PhosphorIconsBold.caretDown, size: 12, color: fg),
        ],
      ),
      onSelected: (_) => onTap(),
    );
  }
}
