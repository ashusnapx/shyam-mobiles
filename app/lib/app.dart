import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router.dart';
import 'core/theme/theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Shyam Mobiles',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        themeMode: ThemeMode.light, // light-only by product decision, even when the phone is in dark mode
        routerConfig: ref.watch(routerProvider),
        // Layouts are checked up to 1.3x; beyond that cards and the nav bar start clipping.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          // Transparent gesture/nav bar so content draws behind it; dark icons on the light UI.
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
          child: SkeletonizerConfig(
            // A slow, soft grey pulse instead of the default fast shimmer; crossfades into content.
            data: SkeletonizerConfigData(
              effectResolver: (_) => const PulseEffect(
                from: Color(0xFFF3F3F3),
                to: Color(0xFFE8E8E8),
                duration: Duration(milliseconds: 1600),
              ),
              enableSwitchAnimation: true,
            ),
            child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
          ),
        ),
      );
}
