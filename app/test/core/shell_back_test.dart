// Back on another tab's first screen goes Home instead of leaving the app (Home → Guards opens the Search tab, and
// Back there used to close the app).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/router.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';

void main() {
  testWidgets('Back on the Search tab goes Home; Back on Home is left to the system', (tester) async {
    GoRoute tab(String path) => GoRoute(path: path, builder: (_, _) => Scaffold(body: Text('TAB $path')));
    final router = GoRouter(initialLocation: '/', routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          for (final p in ['/', '/search', '/repairs', '/cart', '/account']) StatefulShellBranch(routes: [tab(p)]),
        ],
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isAdminProvider.overrideWith((ref) async => false),
        cartCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp.router(theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'), routerConfig: router),
    ));
    router.go('/search?category=screen-guards');
    await tester.pumpAndSettle();
    expect(find.text('TAB /search'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('TAB /'), findsOneWidget, reason: 'Back from another tab lands on Home');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');

    await tester.binding.handlePopRoute(); // Home: nothing to pop, so the system may close the app
    await tester.pumpAndSettle();
    expect(find.text('TAB /'), findsOneWidget);
  });
}
