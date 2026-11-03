// A policy page inside the app: the app's own bar and title, our clean URL loaded with JavaScript off, other sites
// kept out of the WebView, and the house error with Try again when it can't load. The platform WebView is faked.
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/account/screens/policy_screen.dart';
import 'package:shyam_mobiles/features/account/widgets/policies.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const site = 'https://shyam-mobiles.web.app/';

void main() {
  late _FakeWebView web;
  setUp(() => WebViewPlatform.instance = _FakePlatform((w) => web = w));

  Future<void> open(WidgetTester tester, String page, {String base = site}) => tester.pumpWidget(MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/policy/$page', routes: [
          GoRoute(path: '/policy/:page', builder: (_, s) => PolicyScreen(page: s.pathParameters['page']!, base: base)),
        ]),
      ));

  test('every row opens the clean URL firebase.json serves', () {
    expect(policyPages.keys.map(policyPath), ['/', '/privacy', '/terms', '/refunds', '/shipping', '/contact', '/delete-account']);
    expect(policyPage('/'), 'about');
    expect(policyPage('/terms'), 'terms');
    expect(policyPage('/open'), isNull);
  });

  testWidgets('loads our page under its title, with JavaScript off', (tester) async {
    await open(tester, 'privacy');
    expect(find.widgetWithText(AppBar, 'Privacy policy'), findsOneWidget);
    expect(web.loaded, [Uri.parse('https://shyam-mobiles.web.app/privacy')]);
    expect(web.javaScript, JavaScriptMode.disabled);

    Future<NavigationDecision> go(String url) async => web.nav.onNavigationRequest!(NavigationRequest(url: url, isMainFrame: true));
    expect(await go('https://shyam-mobiles.web.app/privacy#rights'), NavigationDecision.navigate);
    expect(await go('https://evil.example/privacy'), NavigationDecision.prevent, reason: 'other sites never load in here');
    expect(await go('http://shyam-mobiles.web.app/privacy'), NavigationDecision.prevent);
    expect(await go('tel:+917987559272'), NavigationDecision.prevent, reason: 'the dialler opens it');
    expect(await go('mailto:shop@example.com'), NavigationDecision.prevent, reason: 'the email app opens it');
    await tester.pump();

    // another of our pages is its own screen, so Back comes back here
    expect(await go('https://shyam-mobiles.web.app/terms'), NavigationDecision.prevent);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Terms of use'), findsOneWidget);
    expect(web.loaded, [Uri.parse('https://shyam-mobiles.web.app/terms')]);
  });

  testWidgets('offline: the house error with Try again, which loads the page again', (tester) async {
    await open(tester, 'refunds');
    web.nav.onWebResourceError!(const WebResourceError(
      errorCode: -2,
      description: 'net::ERR_INTERNET_DISCONNECTED',
      isForMainFrame: true,
    ));
    await tester.pump();
    expect(find.widgetWithText(AppBar, 'Returns & refunds'), findsOneWidget);
    expect(find.text('Couldn’t load this'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Couldn’t load this'), findsNothing);
    expect(web.loaded, hasLength(2));
  });

  testWidgets('a 404 for the page is an error; one for a font or the stylesheet is not', (tester) async {
    await open(tester, 'terms');
    HttpResponseError miss(String path) => HttpResponseError(
          request: WebResourceRequest(uri: Uri.parse('https://shyam-mobiles.web.app$path')),
          response: const WebResourceResponse(uri: null, statusCode: 404),
        );
    web.nav.onHttpError!(miss('/style.css'));
    await tester.pump();
    expect(find.text('Couldn’t load this'), findsNothing);
    web.nav.onHttpError!(miss('/terms'));
    await tester.pump();
    expect(find.text('Couldn’t load this'), findsOneWidget);
  });

  testWidgets('before POLICIES_URL is set it says so instead of loading', (tester) async {
    await open(tester, 'about', base: '');
    expect(find.widgetWithText(AppBar, 'About Shyam Mobiles'), findsOneWidget);
    expect(find.text('Our policy pages go live before launch.'), findsOneWidget);
  });
}

class _FakePlatform extends WebViewPlatform {
  _FakePlatform(this.created);

  final void Function(_FakeWebView) created;

  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) {
    final web = _FakeWebView(params);
    created(web);
    return web;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) =>
      _FakeNavigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) => _FakeWidget(params);
}

class _FakeWebView extends PlatformWebViewController {
  _FakeWebView(super.params) : super.implementation();

  final loaded = <Uri>[];
  JavaScriptMode? javaScript;
  late _FakeNavigation nav;

  @override
  Future<void> loadRequest(LoadRequestParams params) async => loaded.add(params.uri);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async => javaScript = javaScriptMode;

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async => nav = handler as _FakeNavigation;
}

class _FakeNavigation extends PlatformNavigationDelegate {
  _FakeNavigation(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  WebResourceErrorCallback? onWebResourceError;
  HttpResponseErrorCallback? onHttpError;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async =>
      this.onNavigationRequest = onNavigationRequest;

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async =>
      this.onWebResourceError = onWebResourceError;

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async => this.onHttpError = onHttpError;

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}
}

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
