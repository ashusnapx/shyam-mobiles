import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../../offers/data/offers.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/offers_admin.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

/// Product groups ("Diwali picks", "Under ₹999") that offers can target.
class AdminGroupsScreen extends ConsumerWidget {
  const AdminGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminCollectionsProvider);
    final c = Theme.of(context).colorScheme;
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Product groups')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/admin/groups/new'),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('New group'),
        ),
        body: AsyncBody<List<Collection>>(
          value: value,
          onRetry: () => ref.invalidate(adminCollectionsProvider),
          loading: const Center(child: CircularProgressIndicator()),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: PhosphorIconsRegular.stack,
                  title: 'No groups yet',
                  message: 'Group products like “Diwali picks”, then point an offer at the group.',
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(adminCollectionsProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final g in list)
                        ListTile(
                          key: ValueKey(g.id),
                          minTileHeight: 64,
                          shape: Border(bottom: BorderSide(color: c.outlineVariant)),
                          leading: const Icon(PhosphorIconsRegular.stack),
                          title: Text(g.name),
                          subtitle: Text('${g.productIds.length} product${g.productIds.length == 1 ? '' : 's'}'),
                          trailing: const Icon(PhosphorIconsRegular.caretRight, size: 18),
                          onTap: () => context.push('/admin/groups/${g.id}'),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// `/admin/groups/new` and `/admin/groups/:id`.
class AdminGroupEditScreen extends ConsumerWidget {
  const AdminGroupEditScreen({super.key, this.groupId});

  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(adminCollectionsProvider);
    final products = ref.watch(adminProductsProvider);
    final error = groups.error ?? products.error;
    final title = groupId == null ? 'New group' : 'Edit group';
    final group = groups.value?.where((g) => g.id == groupId).firstOrNull;
    return AdminGate(
      child: groups.hasValue && products.hasValue && (groupId == null || group != null)
          ? _Editor(key: ValueKey(groupId), title: title, group: group, products: products.value!)
          : Scaffold(
              appBar: AppBar(title: Text(title)),
              body: error != null
                  ? ErrorView(
                      error: error,
                      onRetry: () => ref
                        ..invalidate(adminCollectionsProvider)
                        ..invalidate(adminProductsProvider),
                    )
                  : groups.hasValue
                      ? const EmptyState(icon: PhosphorIconsRegular.stack, title: 'This group was deleted')
                      : const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.title, required this.group, required this.products});

  final String title;
  final Collection? group;
  final List<AdminProductRow> products;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late final Collection? _g = widget.group;
  late final _name = TextEditingController(text: _g?.name);
  late final _slug = TextEditingController(text: _g?.slug);
  late Set<String> _products = {...?_g?.productIds};
  late bool _slugEdited = _g != null;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  void _changed() {
    ref.invalidate(adminCollectionsProvider);
    ref.invalidate(availableOffersProvider);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminOffersApiProvider).saveCollection(
            Collection(id: _g?.id, slug: _slug.text.trim(), name: tidy(_name.text), productIds: _products),
            before: _g?.productIds ?? const {},
          );
      _changed();
      if (!mounted) return;
      showMessage(context, 'Group saved');
      context.go('/admin/groups');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmChoice(
      context,
      title: 'Delete “${_g!.name}”?',
      message: 'The products stay in the shop. Offers aimed at this group stop covering them.',
      action: 'Delete group',
      keep: 'Keep group',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminOffersApiProvider).deleteCollection(_g.id!);
      _changed();
      if (!mounted) return;
      showMessage(context, 'Group deleted');
      context.go('/admin/groups');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final p in widget.products) p.id: p.name};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_g != null)
            IconButton(tooltip: 'Delete group', onPressed: _busy ? null : _delete, icon: const Icon(PhosphorIconsRegular.trash)),
        ],
      ),
      bottomNavigationBar: StickyBar(
        child: FilledButton(onPressed: _busy ? null : _save, child: Text(_g == null ? 'Create group' : 'Save group')),
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: 'Name', hintText: 'Diwali picks', counter: LengthCounter(_name, 60)),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: textInput(60),
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  if (_slugEdited) return;
                  final s = slugify(v);
                  _slug.text = s.length <= 60 ? s : s.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
                },
                validator: (v) => checkText(v, min: 2, max: 60, what: 'a name', mustHave: hasLetterOrDigit),
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _slug,
                decoration: const InputDecoration(labelText: 'Short name', helperText: 'Lowercase letters, numbers and dashes'),
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [...slugInput.take(1), const CodePointLimit(60)],
                textInputAction: TextInputAction.done,
                onChanged: (_) => _slugEdited = true,
                validator: (v) => collectionSlugPattern.hasMatch(v ?? '') ? null : 'Use a-z, 0-9 and dashes only',
              ),
              const ListSection('Products'),
              MultiPickerField<String>(
                key: ObjectKey(_products), // rebuilt when a product is taken out below
                label: 'Products in this group',
                options: [for (final p in widget.products) p.id],
                labelOf: (id) => names[id] ?? 'Removed product',
                initialValue: _products,
                searchHint: 'Search products',
                onChanged: (v) => setState(() => _products = v),
              ),
              const SizedBox(height: Space.sm),
              for (final id in _products)
                ListTile(
                  key: ValueKey(id),
                  contentPadding: EdgeInsets.zero,
                  title: Text(names[id] ?? 'Removed product'),
                  trailing: IconButton(
                    tooltip: 'Take ${names[id] ?? 'it'} out',
                    onPressed: () => setState(() => _products = {..._products}..remove(id)),
                    icon: const Icon(PhosphorIconsRegular.xCircle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
