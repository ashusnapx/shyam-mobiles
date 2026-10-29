import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/supabase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15 enforces edge-to-edge; opt in everywhere so 10–14 match. Screens pad for system bars themselves.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initSupabase();
  runApp(const ProviderScope(child: App()));
}
