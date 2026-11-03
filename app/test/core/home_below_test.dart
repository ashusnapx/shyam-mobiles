// A page opened with go() (a shared link, a sign-in return) has nothing below it. Back there used to close the app;
// it goes Home now. Pushed over the tabs, Back still just pops.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/router.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';

Future<GoRouter> _pump(WidgetTester tester) async {
  final root = GlobalKey<NavigatorState>();
  GoRoute tab(String path) => GoRoute(path: path, builder: (_, _) => Scaffold(body: Text('TAB $path')));
  final router = GoRouter(navigatorKey: root, initialLocation: '/', routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(shell: shell),
      branches: [for (final p in ['/', '/search', '/repairs', '/cart', '/account']) StatefulShellBranch(routes: [tab(p)])],
    ),
    GoRoute(path: '/product/:slug', builder: (_, s) => HomeBelow(Scaffold(body: Text('PRODUCT ${s.pathParameters['slug']}')))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [isAdminProvider.overrideWith((ref) async => false), cartCountProvider.overrideWithValue(0)],
    child: MaterialApp.router(theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'), routerConfig: router),
  ));
  return router;
}

void main() {
  testWidgets('a product opened with go(): Back goes Home', (tester) async {
    final router = await _pump(tester);
    router.go('/product/s25');
    await tester.pumpAndSettle();
    expect(find.text('PRODUCT s25'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('TAB /'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });

  testWidgets('a product pushed from the Search tab: Back returns to Search', (tester) async {
    final router = await _pump(tester);
    router.go('/search');
    await tester.pumpAndSettle();
    router.push('/product/s25').ignore();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('TAB /search'), findsOneWidget);
  });
}
