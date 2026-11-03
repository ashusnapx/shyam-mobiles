import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/privacy.dart';
import '../data/profile_repository.dart';

/// Account → Privacy (docs/SECURITY.md §4.2, §4.7): the analytics and crash-report switches, and Download my data.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _exporting = false;

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final data = await ref.read(profileRepositoryProvider).exportMyData(ref.read(currentUserIdProvider)!);
      final json = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(json, name: 'shyam-mobiles-my-data.json', mimeType: 'application/json')],
      ));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(privacyProvider);
    final privacy = ref.read(privacyProvider.notifier);
    final c = choices.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          SwitchListTile(
            title: const Text('Help improve the app'),
            subtitle: const Text('Share which screens and products you use. Never your name, number or address.'),
            value: c?.analytics ?? false,
            onChanged: c == null ? null : privacy.setAnalytics,
          ),
          SwitchListTile(
            title: const Text('Send crash reports'),
            subtitle: const Text('When the app breaks, send what went wrong, with nothing about you.'),
            value: c?.crashReports ?? true,
            onChanged: c == null ? null : privacy.setCrashReports,
          ),
          const Divider(),
          ListTile(
            title: const Text('Download my data'),
            subtitle: const Text('Your profile, addresses, orders, repairs and messages, as one file. Once a day.'),
            trailing: _exporting ? const ButtonSpinner() : null,
            onTap: _exporting ? null : _download,
          ),
        ],
      ),
    );
  }
}
