import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/auth/screens/sign_in_screen.dart';

class _Uid extends Notifier<String?> {
  @override
  String? build() => null;
  void signIn(String id) => state = id;
}

final _uid = NotifierProvider<_Uid, String?>(_Uid.new);

void main() {
  // Regression: pushed over a tab, the router's redirect never saw /sign-in, so signing in left the user stuck here.
  testWidgets('sign-in pushed over a tab leaves for `from` once a session exists', (tester) async {
    final router = GoRouter(initialLocation: '/account', routes: [
      GoRoute(path: '/account', builder: (_, _) => const Scaffold(body: Text('ACCOUNT'))),
      GoRoute(path: '/sign-in', builder: (_, s) => SignInScreen(from: s.uri.queryParameters['from'])),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserIdProvider.overrideWith((ref) => ref.watch(_uid))],
      child: MaterialApp.router(theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'), routerConfig: router),
    ));
    router.push('/sign-in?from=%2Faccount');
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(SignInScreen))).read(_uid.notifier).signIn('user-1');
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsNothing);
    expect(find.text('ACCOUNT'), findsOneWidget);
  });
}
