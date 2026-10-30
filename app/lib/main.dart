import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/deep_links.dart';
import 'core/network.dart';
import 'core/supabase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15 enforces edge-to-edge; opt in everywhere so 10–14 match. Screens pad for system bars themselves.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initSupabase();
  final container = ProviderContainer(retry: noAutoRetry);
  await container.read(networkProvider.notifier).start(); // data-saver signals before the first image loads
  runApp(UncontrolledProviderScope(container: container, child: const App()));
  // a friend's code from a shared link (or a Play install from one) waits for sign-in, then applies once
  unawaited(container.read(pendingReferralProvider.notifier).followInstallReferrer());
}
